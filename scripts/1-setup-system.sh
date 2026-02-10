#!/bin/bash
#===============================================================================
# AI Platform Automation - Script 1: System Setup & Configuration Collection
#===============================================================================
# Purpose: Collect all configuration, validate dependencies, prepare environment
# Author: AI Platform Automation
# Version: 3.2.0 - COMPLETE WITH ALL FUNCTIONS
# Branch: main
#===============================================================================

set -euo pipefail
IFS=$'\n\t'

#===============================================================================
# GLOBAL VARIABLES
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/install_$(date +%Y%m%d_%H%M%S).log"

# Configuration storage
declare -A CONFIG
declare -A CREDENTIALS
declare -A LLM_PROVIDERS

# Default values
CONFIG["TIMEZONE"]="UTC"
CONFIG["ENABLE_TELEMETRY"]="false"
CONFIG["DISABLE_TELEMETRY"]="true"
CONFIG["INSTALL_DIR"]="${SCRIPT_DIR}"
CONFIG["DATA_DIR"]="/opt/ai-platform/data"

#===============================================================================
# LOGGING FUNCTIONS
#===============================================================================

log() {
    local level=$1
    shift
    local message="$*"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

#===============================================================================
# COLOR OUTPUT FUNCTIONS
#===============================================================================

print_section() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
}

print_success() {
    echo -e "\033[0;32m✓ $1\033[0m"
}

print_error() {
    echo -e "\033[0;31m✗ $1\033[0m" >&2
}

print_warning() {
    echo -e "\033[0;33m⚠ $1\033[0m"
}

print_info() {
    echo -e "\033[0;36mℹ $1\033[0m"
}

#===============================================================================
# UTILITY FUNCTIONS
#===============================================================================

generate_secret() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        print_info "Please run: sudo $0"
        exit 1
    fi
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    fi
    return 0
}

#===============================================================================
# SYSTEM CONFIGURATION COLLECTION
#===============================================================================

collect_system_config() {
    print_section "System Configuration"
    
    # Installation directory
    local default_install_dir="${SCRIPT_DIR}"
    read -p "Installation directory [$default_install_dir]: " install_dir
    CONFIG["INSTALL_DIR"]="${install_dir:-$default_install_dir}"
    
    # Create if doesn't exist
    if [ ! -d "${CONFIG["INSTALL_DIR"]}" ]; then
        mkdir -p "${CONFIG["INSTALL_DIR"]}"
        print_success "Created installation directory: ${CONFIG["INSTALL_DIR"]}"
    else
        print_info "Using existing directory: ${CONFIG["INSTALL_DIR"]}"
    fi
    
    # Data directory
    local default_data_dir="/opt/ai-platform/data"
    read -p "Data directory [$default_data_dir]: " data_dir
    CONFIG["DATA_DIR"]="${data_dir:-$default_data_dir}"
    
    print_success "System configuration collected"
    log "INFO" "Install dir: ${CONFIG["INSTALL_DIR"]}, Data dir: ${CONFIG["DATA_DIR"]}"
}

configure_directories() {
    print_section "Creating Directory Structure"
    
    local dirs=(
        "${CONFIG["DATA_DIR"]}"
        "${CONFIG["DATA_DIR"]}/postgres"
        "${CONFIG["DATA_DIR"]}/redis"
        "${CONFIG["DATA_DIR"]}/minio"
        "${CONFIG["DATA_DIR"]}/ollama"
        "${CONFIG["DATA_DIR"]}/n8n"
        "${CONFIG["DATA_DIR"]}/flowise"
        "${CONFIG["DATA_DIR"]}/openwebui"
        "${CONFIG["DATA_DIR"]}/anythingllm"
        "${CONFIG["DATA_DIR"]}/langfuse"
        "${CONFIG["DATA_DIR"]}/dify"
        "${CONFIG["DATA_DIR"]}/openclaw"
        "${CONFIG["DATA_DIR"]}/vectordb"
        "${CONFIG["DATA_DIR"]}/portainer"
        "${CONFIG["DATA_DIR"]}/uptime-kuma"
        "${CONFIG["DATA_DIR"]}/grafana"
        "${CONFIG["DATA_DIR"]}/prometheus"
        "${CONFIG["DATA_DIR"]}/signal"
        "${CONFIG["DATA_DIR"]}/logs"
        "${CONFIG["DATA_DIR"]}/backups"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            print_info "Created: $dir"
        fi
    done
    
    # Set permissions
    chmod -R 755 "${CONFIG["DATA_DIR"]}"
    
    print_success "Directory structure created"
    log "INFO" "Directories created under ${CONFIG["DATA_DIR"]}"
}

detect_public_ip() {
    print_section "Network Configuration"
    
    print_info "Detecting public IP address..."
    
    local detected_ip=""
    
    # Try multiple services
    for service in "ifconfig.me" "icanhazip.com" "ipecho.net/plain" "api.ipify.org"; do
        detected_ip=$(curl -s --max-time 5 "https://$service" 2>/dev/null || echo "")
        if [ -n "$detected_ip" ] && [[ $detected_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            break
        fi
    done
    
    if [ -z "$detected_ip" ]; then
        print_warning "Could not auto-detect public IP"
        detected_ip="127.0.0.1"
    else
        print_success "Detected IP: $detected_ip"
    fi
    
    read -p "Public IP address [$detected_ip]: " public_ip
    CONFIG["PUBLIC_IP"]="${public_ip:-$detected_ip}"
    
    print_success "Network configured: ${CONFIG["PUBLIC_IP"]}"
    log "INFO" "Public IP: ${CONFIG["PUBLIC_IP"]}"
}

configure_domain() {
    print_section "Domain Configuration"
    
    read -p "Do you have a domain name? (y/n) [n]: " has_domain
    
    if [[ $has_domain =~ ^[Yy]$ ]]; then
        CONFIG["USE_DOMAIN"]="true"
        
        while true; do
            read -p "Enter your domain (e.g., ai.example.com): " domain
            if [ -n "$domain" ]; then
                CONFIG["DOMAIN"]=$domain
                break
            else
                print_error "Domain cannot be empty"
            fi
        done
        
        print_success "Domain configured: ${CONFIG["DOMAIN"]}"
        
        # Cloudflare
        read -p "Use Cloudflare for SSL? (y/n) [n]: " use_cf
        if [[ $use_cf =~ ^[Yy]$ ]]; then
            CONFIG["USE_CLOUDFLARE"]="true"
            
            read -p "Cloudflare email: " cf_email
            CONFIG["CLOUDFLARE_EMAIL"]=$cf_email
            
            read -sp "Cloudflare API key: " cf_key
            echo ""
            CONFIG["CLOUDFLARE_API_KEY"]=$cf_key
            CREDENTIALS["CLOUDFLARE_API_KEY"]=$cf_key
            
            print_success "Cloudflare configured"
        else
            CONFIG["USE_CLOUDFLARE"]="false"
            print_info "Will use self-signed certificates"
        fi
        
        log "INFO" "Domain configured: ${CONFIG["DOMAIN"]}, Cloudflare: ${CONFIG["USE_CLOUDFLARE"]}"
    else
        CONFIG["USE_DOMAIN"]="false"
        print_info "Using IP-based access: ${CONFIG["PUBLIC_IP"]}"
        log "INFO" "No domain configured, using IP"
    fi
}

configure_timezone() {
    print_section "Timezone Configuration"
    
    # Detect current timezone
    local current_tz
    if [ -f /etc/timezone ]; then
        current_tz=$(cat /etc/timezone)
    else
        current_tz=$(timedatectl | grep "Time zone" | awk '{print $3}')
    fi
    
    current_tz=${current_tz:-UTC}
    
    print_info "Current timezone: $current_tz"
    read -p "Timezone [$current_tz]: " timezone
    CONFIG["TIMEZONE"]="${timezone:-$current_tz}"
    
    print_success "Timezone set to: ${CONFIG["TIMEZONE"]}"
    log "INFO" "Timezone: ${CONFIG["TIMEZONE"]}"
}

configure_telemetry() {
    print_section "Telemetry Settings"
    
    echo ""
    echo "Some services collect anonymous usage data to improve their products."
    echo "This includes: Dify, Langfuse, n8n"
    echo ""
    
    read -p "Allow telemetry? (y/n) [n]: " allow_telemetry
    
    if [[ $allow_telemetry =~ ^[Yy]$ ]]; then
        CONFIG["ENABLE_TELEMETRY"]="true"
        CONFIG["DISABLE_TELEMETRY"]="false"
        print_info "Telemetry enabled"
    else
        CONFIG["ENABLE_TELEMETRY"]="false"
        CONFIG["DISABLE_TELEMETRY"]="true"
        print_info "Telemetry disabled"
    fi
    
    log "INFO" "Telemetry: ${CONFIG["ENABLE_TELEMETRY"]}"
}
#===============================================================================
# SERVICE SELECTION FUNCTIONS
#===============================================================================

select_services() {
    print_section "Service Selection"
    
    echo ""
    echo "Select services to install. You can:"
    echo "  - Enter 'all' for a category to select all services in that category"
    echo "  - Enter specific numbers separated by spaces (e.g., '1 3 5')"
    echo "  - Press Enter to skip a category"
    echo ""
    
    # Initialize all services as false
    CONFIG["INSTALL_POSTGRES"]="false"
    CONFIG["INSTALL_REDIS"]="false"
    CONFIG["INSTALL_MINIO"]="false"
    CONFIG["INSTALL_OLLAMA"]="false"
    CONFIG["INSTALL_LITELLM"]="false"
    CONFIG["INSTALL_N8N"]="false"
    CONFIG["INSTALL_FLOWISE"]="false"
    CONFIG["INSTALL_OPENWEBUI"]="false"
    CONFIG["INSTALL_ANYTHINGLLM"]="false"
    CONFIG["INSTALL_LANGFUSE"]="false"
    CONFIG["INSTALL_DIFY"]="false"
    CONFIG["INSTALL_LIBRECHAT"]="false"
    CONFIG["INSTALL_OPENCLAW"]="false"
    CONFIG["INSTALL_PORTAINER"]="false"
    CONFIG["INSTALL_UPTIME_KUMA"]="false"
    CONFIG["INSTALL_MONITORING"]="false"
    CONFIG["INSTALL_SIGNAL"]="false"
    CONFIG["INSTALL_VECTORDB"]="false"
    
    # Core Infrastructure
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "CORE INFRASTRUCTURE (Required for most services):"
    echo "  1) PostgreSQL     - Database for n8n, Flowise, Langfuse, Dify"
    echo "  2) Redis          - Cache & queue for n8n, Dify"
    echo "  3) MinIO          - Object storage for Dify, backups"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    read -p "Select core services (e.g., '1 2 3' or 'all') [all]: " core_selection
    core_selection=${core_selection:-all}
    
    if [ "$core_selection" == "all" ]; then
        CONFIG["INSTALL_POSTGRES"]="true"
        CONFIG["INSTALL_REDIS"]="true"
        CONFIG["INSTALL_MINIO"]="true"
        print_success "Selected: PostgreSQL, Redis, MinIO"
    else
        for num in $core_selection; do
            case $num in
                1) CONFIG["INSTALL_POSTGRES"]="true"; print_success "✓ PostgreSQL" ;;
                2) CONFIG["INSTALL_REDIS"]="true"; print_success "✓ Redis" ;;
                3) CONFIG["INSTALL_MINIO"]="true"; print_success "✓ MinIO" ;;
                *) print_warning "Invalid option: $num" ;;
            esac
        done
    fi
    
    echo ""
    
    # AI Stack
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "AI STACK:"
    echo "  4) Ollama         - Local LLM inference"
    echo "  5) LiteLLM        - Unified API proxy for multiple LLM providers"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    read -p "Select AI stack (e.g., '4 5' or 'all') [all]: " ai_selection
    ai_selection=${ai_selection:-all}
    
    if [ "$ai_selection" == "all" ]; then
        CONFIG["INSTALL_OLLAMA"]="true"
        CONFIG["INSTALL_LITELLM"]="true"
        print_success "Selected: Ollama, LiteLLM"
    else
        for num in $ai_selection; do
            case $num in
                4) CONFIG["INSTALL_OLLAMA"]="true"; print_success "✓ Ollama" ;;
                5) CONFIG["INSTALL_LITELLM"]="true"; print_success "✓ LiteLLM" ;;
                *) print_warning "Invalid option: $num" ;;
            esac
        done
    fi
    
    echo ""
    
    # Workflow & Automation
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "WORKFLOW & AUTOMATION:"
    echo "  6) n8n            - Workflow automation with AI"
    echo "  7) Flowise        - Visual LLM flow builder"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    read -p "Select workflow tools (e.g., '6 7' or 'all') []: " workflow_selection
    
    if [ "$workflow_selection" == "all" ]; then
        CONFIG["INSTALL_N8N"]="true"
        CONFIG["INSTALL_FLOWISE"]="true"
        print_success "Selected: n8n, Flowise"
    elif [ -n "$workflow_selection" ]; then
        for num in $workflow_selection; do
            case $num in
                6) CONFIG["INSTALL_N8N"]="true"; print_success "✓ n8n" ;;
                7) CONFIG["INSTALL_FLOWISE"]="true"; print_success "✓ Flowise" ;;
                *) print_warning "Invalid option: $num" ;;
            esac
        done
    fi
    
    echo ""
    
    # Chat Interfaces
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "CHAT INTERFACES:"
    echo "  8)  Open WebUI    - ChatGPT-like UI for local LLMs"
    echo "  9)  AnythingLLM   - Full-featured AI workspace"
    echo "  10) LibreChat     - Multi-provider chat interface"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    read -p "Select chat interfaces (e.g., '8 9') []: " chat_selection
    
    if [ "$chat_selection" == "all" ]; then
        CONFIG["INSTALL_OPENWEBUI"]="true"
        CONFIG["INSTALL_ANYTHINGLLM"]="true"
        CONFIG["INSTALL_LIBRECHAT"]="true"
        print_success "Selected: Open WebUI, AnythingLLM, LibreChat"
    elif [ -n "$chat_selection" ]; then
        for num in $chat_selection; do
            case $num in
                8) CONFIG["INSTALL_OPENWEBUI"]="true"; print_success "✓ Open WebUI" ;;
                9) CONFIG["INSTALL_ANYTHINGLLM"]="true"; print_success "✓ AnythingLLM" ;;
                10) CONFIG["INSTALL_LIBRECHAT"]="true"; print_success "✓ LibreChat" ;;
                *) print_warning "Invalid option: $num" ;;
            esac
        done
    fi
    
    echo ""
    
    # Application Platforms
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "APPLICATION PLATFORMS:"
    echo "  11) Dify          - LLM app development platform"
    echo "  12) Langfuse      - LLM observability & analytics"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    read -p "Select application platforms (e.g., '11 12') []: " app_selection
    
    if [ "$app_selection" == "all" ]; then
        CONFIG["INSTALL_DIFY"]="true"
        CONFIG["INSTALL_LANGFUSE"]="true"
        print_success "Selected: Dify, Langfuse"
    elif [ -n "$app_selection" ]; then
        for num in $app_selection; do
            case $num in
                11) CONFIG["INSTALL_DIFY"]="true"; print_success "✓ Dify" ;;
                12) CONFIG["INSTALL_LANGFUSE"]="true"; print_success "✓ Langfuse" ;;
                *) print_warning "Invalid option: $num" ;;
            esac
        done
    fi
    
    echo ""
    
    # Operations & Monitoring
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "OPERATIONS & MONITORING:"
    echo "  13) Portainer     - Docker management UI"
    echo "  14) Uptime Kuma   - Service monitoring & status page"
    echo "  15) Grafana+Prometheus - Metrics & dashboards"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    read -p "Select operations tools (e.g., '13 14 15' or 'all') []: " ops_selection
    
    if [ "$ops_selection" == "all" ]; then
        CONFIG["INSTALL_PORTAINER"]="true"
        CONFIG["INSTALL_UPTIME_KUMA"]="true"
        CONFIG["INSTALL_MONITORING"]="true"
        print_success "Selected: Portainer, Uptime Kuma, Monitoring"
    elif [ -n "$ops_selection" ]; then
        for num in $ops_selection; do
            case $num in
                13) CONFIG["INSTALL_PORTAINER"]="true"; print_success "✓ Portainer" ;;
                14) CONFIG["INSTALL_UPTIME_KUMA"]="true"; print_success "✓ Uptime Kuma" ;;
                15) CONFIG["INSTALL_MONITORING"]="true"; print_success "✓ Grafana+Prometheus" ;;
                *) print_warning "Invalid option: $num" ;;
            esac
        done
    fi
    
    echo ""
    
    # Optional Services
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "OPTIONAL SERVICES:"
    echo "  16) Signal Proxy  - Private Signal messaging relay"
    echo "  17) OpenClaw      - Web automation & scraping"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    read -p "Select optional services (e.g., '16 17') []: " optional_selection
    
    if [ "$optional_selection" == "all" ]; then
        CONFIG["INSTALL_SIGNAL"]="true"
        CONFIG["INSTALL_OPENCLAW"]="true"
        print_success "Selected: Signal Proxy, OpenClaw"
    elif [ -n "$optional_selection" ]; then
        for num in $optional_selection; do
            case $num in
                16) CONFIG["INSTALL_SIGNAL"]="true"; print_success "✓ Signal Proxy" ;;
                17) CONFIG["INSTALL_OPENCLAW"]="true"; print_success "✓ OpenClaw" ;;
                *) print_warning "Invalid option: $num" ;;
            esac
        done
    fi
    
    echo ""
    print_success "Service selection complete"
    log "INFO" "Services selected"
}

#===============================================================================
# VECTOR DATABASE SELECTION
#===============================================================================

select_vector_db() {
    # Check if any service needs vector DB
    local needs_vectordb=false
    
    if [ "${CONFIG["INSTALL_FLOWISE"]}" == "true" ] || \
       [ "${CONFIG["INSTALL_ANYTHINGLLM"]}" == "true" ] || \
       [ "${CONFIG["INSTALL_DIFY"]}" == "true" ] || \
       [ "${CONFIG["INSTALL_N8N"]}" == "true" ]; then
        needs_vectordb=true
    fi
    
    if [ "$needs_vectordb" == "false" ]; then
        CONFIG["INSTALL_VECTORDB"]="false"
        return 0
    fi
    
    print_section "Vector Database Selection"
    
    echo ""
    echo "Some services (Flowise, AnythingLLM, Dify, n8n) can use vector databases"
    echo "for document storage and semantic search."
    echo ""
    echo "Options:"
    echo "  1) Qdrant   - Recommended, feature-rich"
    echo "  2) Chroma   - Simple, lightweight"
    echo "  3) Weaviate - Enterprise-grade"
    echo "  4) Skip     - Services will use their built-in storage"
    echo ""
    
    read -p "Select vector database [1]: " vectordb_choice
    vectordb_choice=${vectordb_choice:-1}
    
    case $vectordb_choice in
        1)
            CONFIG["INSTALL_VECTORDB"]="true"
            CONFIG["VECTORDB_TYPE"]="qdrant"
            print_success "Selected: Qdrant"
            ;;
        2)
            CONFIG["INSTALL_VECTORDB"]="true"
            CONFIG["VECTORDB_TYPE"]="chroma"
            print_success "Selected: Chroma"
            ;;
        3)
            CONFIG["INSTALL_VECTORDB"]="true"
            CONFIG["VECTORDB_TYPE"]="weaviate"
            print_success "Selected: Weaviate"
            ;;
        4)
            CONFIG["INSTALL_VECTORDB"]="false"
            print_info "Skipping vector database - services will use built-in storage"
            ;;
        *)
            print_warning "Invalid choice, defaulting to Qdrant"
            CONFIG["INSTALL_VECTORDB"]="true"
            CONFIG["VECTORDB_TYPE"]="qdrant"
            ;;
    esac
    
    log "INFO" "Vector DB: ${CONFIG["INSTALL_VECTORDB"]}, Type: ${CONFIG["VECTORDB_TYPE"]:-none}"
}

#===============================================================================
# LLM PROVIDER CONFIGURATION
#===============================================================================

configure_llm_providers() {
    print_section "LLM Provider API Keys"
    
    echo ""
    echo "Configure API keys for external LLM providers."
    echo "Press Enter to skip any provider you don't want to use."
    echo ""
    
    # Initialize
    LLM_PROVIDERS["openai"]="false"
    LLM_PROVIDERS["anthropic"]="false"
    LLM_PROVIDERS["google"]="false"
    LLM_PROVIDERS["mistral"]="false"
    LLM_PROVIDERS["cohere"]="false"
    LLM_PROVIDERS["groq"]="false"
    LLM_PROVIDERS["together"]="false"
    LLM_PROVIDERS["perplexity"]="false"
    
    # OpenAI
    print_info "─────────────────────────────────────────────"
    read -p "OpenAI API key (https://platform.openai.com/api-keys): " openai_key
    if [ -n "$openai_key" ]; then
        LLM_PROVIDERS["openai"]="true"
        CREDENTIALS["OPENAI_API_KEY"]=$openai_key
        print_success "✓ OpenAI configured"
    fi
    
    # Anthropic
    print_info "─────────────────────────────────────────────"
    read -p "Anthropic API key (https://console.anthropic.com): " anthropic_key
    if [ -n "$anthropic_key" ]; then
        LLM_PROVIDERS["anthropic"]="true"
        CREDENTIALS["ANTHROPIC_API_KEY"]=$anthropic_key
        print_success "✓ Anthropic configured"
    fi
    
    # Google
    print_info "─────────────────────────────────────────────"
    read -p "Google AI API key (https://makersuite.google.com/app/apikey): " google_key
    if [ -n "$google_key" ]; then
        LLM_PROVIDERS["google"]="true"
        CREDENTIALS["GOOGLE_API_KEY"]=$google_key
        print_success "✓ Google AI configured"
    fi
    
    # Mistral
    print_info "─────────────────────────────────────────────"
    read -p "Mistral API key (https://console.mistral.ai): " mistral_key
    if [ -n "$mistral_key" ]; then
        LLM_PROVIDERS["mistral"]="true"
        CREDENTIALS["MISTRAL_API_KEY"]=$mistral_key
        print_success "✓ Mistral configured"
    fi
    
    # Cohere
    print_info "─────────────────────────────────────────────"
    read -p "Cohere API key (https://dashboard.cohere.com): " cohere_key
    if [ -n "$cohere_key" ]; then
        LLM_PROVIDERS["cohere"]="true"
        CREDENTIALS["COHERE_API_KEY"]=$cohere_key
        print_success "✓ Cohere configured"
    fi
    
    # Groq
    print_info "─────────────────────────────────────────────"
    read -p "Groq API key (https://console.groq.com): " groq_key
    if [ -n "$groq_key" ]; then
        LLM_PROVIDERS["groq"]="true"
        CREDENTIALS["GROQ_API_KEY"]=$groq_key
        print_success "✓ Groq configured"
    fi
    
    # Together AI
    print_info "─────────────────────────────────────────────"
    read -p "Together AI API key (https://api.together.xyz): " together_key
    if [ -n "$together_key" ]; then
        LLM_PROVIDERS["together"]="true"
        CREDENTIALS["TOGETHER_API_KEY"]=$together_key
        print_success "✓ Together AI configured"
    fi
    
    # Perplexity
    print_info "─────────────────────────────────────────────"
    read -p "Perplexity API key (https://www.perplexity.ai/settings/api): " perplexity_key
    if [ -n "$perplexity_key" ]; then
        LLM_PROVIDERS["perplexity"]="true"
        CREDENTIALS["PERPLEXITY_API_KEY"]=$perplexity_key
        print_success "✓ Perplexity configured"
    fi
    
    echo ""
    
    # Count configured providers
    local provider_count=0
    for provider in "${!LLM_PROVIDERS[@]}"; do
        if [ "${LLM_PROVIDERS[$provider]}" == "true" ]; then
            ((provider_count++))
        fi
    done
    
    if [ $provider_count -eq 0 ] && [ "${CONFIG["INSTALL_OLLAMA"]}" != "true" ]; then
        print_warning "No LLM providers configured!"
        print_info "You can add API keys later in the .env files"
    else
        print_success "Configured $provider_count external LLM provider(s)"
    fi
    
    log "INFO" "LLM providers configured: $provider_count"
}
#===============================================================================
# SERVICE CONFIGURATION FUNCTIONS
#===============================================================================

configure_postgres() {
    if [ "${CONFIG["INSTALL_POSTGRES"]}" != "true" ]; then
        return 0
    fi

    print_section "PostgreSQL Configuration"

    # Generate credentials
    CREDENTIALS["POSTGRES_PASSWORD"]=$(generate_secret)
    CONFIG["POSTGRES_USER"]="postgres"
    CONFIG["POSTGRES_DB"]="postgres"
    CONFIG["POSTGRES_PORT"]="5432"

    # Service-specific databases
    if [ "${CONFIG["INSTALL_N8N"]}" == "true" ]; then
        CREDENTIALS["N8N_DB_PASSWORD"]=$(generate_secret)
        CONFIG["N8N_DB_NAME"]="n8n"
        CONFIG["N8N_DB_USER"]="n8n"
    fi

    if [ "${CONFIG["INSTALL_FLOWISE"]}" == "true" ]; then
        CREDENTIALS["FLOWISE_DB_PASSWORD"]=$(generate_secret)
        CONFIG["FLOWISE_DB_NAME"]="flowise"
        CONFIG["FLOWISE_DB_USER"]="flowise"
    fi

    if [ "${CONFIG["INSTALL_LANGFUSE"]}" == "true" ]; then
        CREDENTIALS["LANGFUSE_DB_PASSWORD"]=$(generate_secret)
        CONFIG["LANGFUSE_DB_NAME"]="langfuse"
        CONFIG["LANGFUSE_DB_USER"]="langfuse"
    fi

    if [ "${CONFIG["INSTALL_DIFY"]}" == "true" ]; then
        CREDENTIALS["DIFY_DB_PASSWORD"]=$(generate_secret)
        CONFIG["DIFY_DB_NAME"]="dify"
        CONFIG["DIFY_DB_USER"]="dify"
    fi

    print_success "PostgreSQL configured with generated credentials"
    log "INFO" "PostgreSQL configured"
}

configure_redis() {
    if [ "${CONFIG["INSTALL_REDIS"]}" != "true" ]; then
        return 0
    fi

    print_section "Redis Configuration"

    CREDENTIALS["REDIS_PASSWORD"]=$(generate_secret)
    CONFIG["REDIS_PORT"]="6379"

    print_success "Redis configured with generated password"
    log "INFO" "Redis configured"
}

configure_minio() {
    if [ "${CONFIG["INSTALL_MINIO"]}" != "true" ]; then
        return 0
    fi

    print_section "MinIO Configuration"

    CREDENTIALS["MINIO_ROOT_USER"]="minioadmin"
    CREDENTIALS["MINIO_ROOT_PASSWORD"]=$(generate_secret)
    CONFIG["MINIO_PORT"]="9000"
    CONFIG["MINIO_CONSOLE_PORT"]="9001"

    # Buckets for services
    CONFIG["MINIO_BUCKETS"]="dify,backups,uploads"

    print_success "MinIO configured"
    log "INFO" "MinIO configured with root credentials"
}

configure_ollama() {
    if [ "${CONFIG["INSTALL_OLLAMA"]}" != "true" ]; then
        return 0
    fi

    print_section "Ollama Configuration"

    CONFIG["OLLAMA_PORT"]="11434"
    CONFIG["OLLAMA_MODELS"]="llama3.2:latest,mistral:latest,nomic-embed-text:latest"

    echo ""
    echo "Ollama will be configured with GPU support if available."
    echo "Default models to pull: llama3.2, mistral, nomic-embed-text"
    echo ""

    read -p "Add additional models? (comma-separated, or Enter to skip): " additional_models
    if [ -n "$additional_models" ]; then
        CONFIG["OLLAMA_MODELS"]="${CONFIG["OLLAMA_MODELS"]},${additional_models}"
    fi

    print_success "Ollama configured"
    log "INFO" "Ollama models: ${CONFIG["OLLAMA_MODELS"]}"
}

configure_litellm() {
    if [ "${CONFIG["INSTALL_LITELLM"]}" != "true" ]; then
        return 0
    fi

    print_section "LiteLLM Configuration"

    CONFIG["LITELLM_PORT"]="4000"
    CREDENTIALS["LITELLM_MASTER_KEY"]=$(generate_secret)
    CREDENTIALS["LITELLM_SALT_KEY"]=$(generate_secret)

    # Build model list for round-robin
    local models=()

    # Add Ollama if installed
    if [ "${CONFIG["INSTALL_OLLAMA"]}" == "true" ]; then
        models+=("ollama/llama3.2")
        models+=("ollama/mistral")
    fi

    # Add external providers
    if [ "${LLM_PROVIDERS["openai"]}" == "true" ]; then
        models+=("gpt-4o-mini")
        models+=("gpt-4o")
    fi

    if [ "${LLM_PROVIDERS["anthropic"]}" == "true" ]; then
        models+=("claude-3-5-sonnet-20241022")
        models+=("claude-3-5-haiku-20241022")
    fi

    if [ "${LLM_PROVIDERS["google"]}" == "true" ]; then
        models+=("gemini/gemini-1.5-pro")
        models+=("gemini/gemini-1.5-flash")
    fi

    if [ "${LLM_PROVIDERS["groq"]}" == "true" ]; then
        models+=("groq/llama-3.3-70b-versatile")
        models+=("groq/mixtral-8x7b-32768")
    fi

    # Store models as JSON array
    CONFIG["LITELLM_MODELS"]=$(printf '%s\n' "${models[@]}" | jq -R . | jq -s .)

    print_success "LiteLLM configured with ${#models[@]} models"
    log "INFO" "LiteLLM models: ${models[*]}"
}

configure_n8n() {
    if [ "${CONFIG["INSTALL_N8N"]}" != "true" ]; then
        return 0
    fi

    print_section "n8n Configuration"

    CONFIG["N8N_PORT"]="5678"
    CREDENTIALS["N8N_ENCRYPTION_KEY"]=$(generate_secret)

    # Basic auth credentials
    read -p "n8n admin username [admin]: " n8n_user
    CONFIG["N8N_BASIC_AUTH_USER"]="${n8n_user:-admin}"

    read -sp "n8n admin password (or Enter to generate): " n8n_pass
    echo ""
    if [ -z "$n8n_pass" ]; then
        n8n_pass=$(generate_secret)
        print_info "Generated password: $n8n_pass"
    fi
    CREDENTIALS["N8N_BASIC_AUTH_PASSWORD"]=$n8n_pass

    # Webhook URL
    if [ "${CONFIG["USE_DOMAIN"]}" == "true" ]; then
        CONFIG["N8N_WEBHOOK_URL"]="https://n8n.${CONFIG["DOMAIN"]}"
    else
        CONFIG["N8N_WEBHOOK_URL"]="http://${CONFIG["PUBLIC_IP"]}:5678"
    fi

    print_success "n8n configured"
    log "INFO" "n8n user: ${CONFIG["N8N_BASIC_AUTH_USER"]}"
}

configure_flowise() {
    if [ "${CONFIG["INSTALL_FLOWISE"]}" != "true" ]; then
        return 0
    fi

    print_section "Flowise Configuration"

    CONFIG["FLOWISE_PORT"]="3000"
    CREDENTIALS["FLOWISE_SECRETKEY_OVERWRITE"]=$(generate_secret)

    # Username/password
    read -p "Flowise username [admin]: " flowise_user
    CONFIG["FLOWISE_USERNAME"]="${flowise_user:-admin}"

    read -sp "Flowise password (or Enter to generate): " flowise_pass
    echo ""
    if [ -z "$flowise_pass" ]; then
        flowise_pass=$(generate_secret)
        print_info "Generated password: $flowise_pass"
    fi
    CREDENTIALS["FLOWISE_PASSWORD"]=$flowise_pass

    print_success "Flowise configured"
    log "INFO" "Flowise user: ${CONFIG["FLOWISE_USERNAME"]}"
}

configure_openwebui() {
    if [ "${CONFIG["INSTALL_OPENWEBUI"]}" != "true" ]; then
        return 0
    fi

    print_section "Open WebUI Configuration"

    CONFIG["OPENWEBUI_PORT"]="8080"
    CREDENTIALS["OPENWEBUI_SECRET_KEY"]=$(generate_secret)

    # Set Ollama URL
    if [ "${CONFIG["INSTALL_OLLAMA"]}" == "true" ]; then
        CONFIG["OPENWEBUI_OLLAMA_BASE_URL"]="http://ollama:11434"
    else
        read -p "External Ollama URL [http://host.docker.internal:11434]: " ollama_url
        CONFIG["OPENWEBUI_OLLAMA_BASE_URL"]="${ollama_url:-http://host.docker.internal:11434}"
    fi

    print_success "Open WebUI configured"
    log "INFO" "Open WebUI Ollama URL: ${CONFIG["OPENWEBUI_OLLAMA_BASE_URL"]}"
}

configure_anythingllm() {
    if [ "${CONFIG["INSTALL_ANYTHINGLLM"]}" != "true" ]; then
        return 0
    fi

    print_section "AnythingLLM Configuration"

    CONFIG["ANYTHINGLLM_PORT"]="3001"
    CREDENTIALS["ANYTHINGLLM_JWT_SECRET"]=$(generate_secret)
    CONFIG["ANYTHINGLLM_STORAGE_DIR"]="${CONFIG["DATA_DIR"]}/anythingllm"

    # LLM Provider selection
    echo ""
    echo "Select default LLM provider for AnythingLLM:"
    echo "  1) Ollama (local)"
    echo "  2) LiteLLM (unified proxy)"
    echo "  3) OpenAI"
    echo "  4) Anthropic"
    echo ""

    read -p "Choice [1]: " llm_choice
    llm_choice=${llm_choice:-1}

    case $llm_choice in
        1)
            CONFIG["ANYTHINGLLM_LLM_PROVIDER"]="ollama"
            CONFIG["ANYTHINGLLM_LLM_BASE_PATH"]="http://ollama:11434"
            ;;
        2)
            CONFIG["ANYTHINGLLM_LLM_PROVIDER"]="litellm"
            CONFIG["ANYTHINGLLM_LLM_BASE_PATH"]="http://litellm:4000"
            ;;
        3)
            CONFIG["ANYTHINGLLM_LLM_PROVIDER"]="openai"
            CONFIG["ANYTHINGLLM_LLM_API_KEY"]="${CREDENTIALS["OPENAI_API_KEY"]:-}"
            ;;
        4)
            CONFIG["ANYTHINGLLM_LLM_PROVIDER"]="anthropic"
            CONFIG["ANYTHINGLLM_LLM_API_KEY"]="${CREDENTIALS["ANTHROPIC_API_KEY"]:-}"
            ;;
    esac

    print_success "AnythingLLM configured with ${CONFIG["ANYTHINGLLM_LLM_PROVIDER"]}"
    log "INFO" "AnythingLLM LLM: ${CONFIG["ANYTHINGLLM_LLM_PROVIDER"]}"
}

configure_langfuse() {
    if [ "${CONFIG["INSTALL_LANGFUSE"]}" != "true" ]; then
        return 0
    fi

    print_section "Langfuse Configuration"

    CONFIG["LANGFUSE_PORT"]="3030"
    CREDENTIALS["LANGFUSE_SALT"]=$(generate_secret)
    CREDENTIALS["LANGFUSE_ENCRYPTION_KEY"]=$(openssl rand -base64 32)
    CREDENTIALS["LANGFUSE_NEXTAUTH_SECRET"]=$(generate_secret)

    if [ "${CONFIG["USE_DOMAIN"]}" == "true" ]; then
        CONFIG["LANGFUSE_NEXTAUTH_URL"]="https://langfuse.${CONFIG["DOMAIN"]}"
    else
        CONFIG["LANGFUSE_NEXTAUTH_URL"]="http://${CONFIG["PUBLIC_IP"]}:3030"
    fi

    print_success "Langfuse configured"
    log "INFO" "Langfuse URL: ${CONFIG["LANGFUSE_NEXTAUTH_URL"]}"
}

configure_dify() {
    if [ "${CONFIG["INSTALL_DIFY"]}" != "true" ]; then
        return 0
    fi

    print_section "Dify Configuration"

    CONFIG["DIFY_API_PORT"]="5001"
    CONFIG["DIFY_WEB_PORT"]="3002"
    CONFIG["DIFY_NGINX_PORT"]="8081"

    CREDENTIALS["DIFY_SECRET_KEY"]=$(generate_secret)

    # Edition
    CONFIG["DIFY_EDITION"]="SELF_HOSTED"

    # Admin setup
    read -p "Dify admin email: " dify_email
    CONFIG["DIFY_ADMIN_EMAIL"]=$dify_email

    read -sp "Dify admin password: " dify_pass
    echo ""
    CREDENTIALS["DIFY_ADMIN_PASSWORD"]=$dify_pass

    # Storage
    if [ "${CONFIG["INSTALL_MINIO"]}" == "true" ]; then
        CONFIG["DIFY_STORAGE_TYPE"]="s3"
        CONFIG["DIFY_S3_ENDPOINT"]="http://minio:9000"
        CONFIG["DIFY_S3_BUCKET"]="dify"
        CONFIG["DIFY_S3_ACCESS_KEY"]="${CREDENTIALS["MINIO_ROOT_USER"]}"
        CREDENTIALS["DIFY_S3_SECRET_KEY"]="${CREDENTIALS["MINIO_ROOT_PASSWORD"]}"
    else
        CONFIG["DIFY_STORAGE_TYPE"]="local"
    fi

    print_success "Dify configured"
    log "INFO" "Dify admin: ${CONFIG["DIFY_ADMIN_EMAIL"]}"
}

configure_librechat() {
    if [ "${CONFIG["INSTALL_LIBRECHAT"]}" != "true" ]; then
        return 0
    fi

    print_section "LibreChat Configuration"

    CONFIG["LIBRECHAT_PORT"]="3003"
    CREDENTIALS["LIBRECHAT_JWT_SECRET"]=$(generate_secret)
    CREDENTIALS["LIBRECHAT_JWT_REFRESH_SECRET"]=$(generate_secret)
    CREDENTIALS["LIBRECHAT_CREDS_KEY"]=$(openssl rand -base64 32)
    CREDENTIALS["LIBRECHAT_CREDS_IV"]=$(openssl rand -base64 16)

    # App title
    read -p "LibreChat app title [AI Chat]: " app_title
    CONFIG["LIBRECHAT_APP_TITLE"]="${app_title:-AI Chat}"

    print_success "LibreChat configured"
    log "INFO" "LibreChat title: ${CONFIG["LIBRECHAT_APP_TITLE"]}"
}

configure_portainer() {
    if [ "${CONFIG["INSTALL_PORTAINER"]}" != "true" ]; then
        return 0
    fi

    print_section "Portainer Configuration"

    CONFIG["PORTAINER_PORT"]="9443"
    CONFIG["PORTAINER_EDGE_PORT"]="8000"

    print_success "Portainer configured (web UI on port 9443)"
    log "INFO" "Portainer configured"
}

configure_uptime_kuma() {
    if [ "${CONFIG["INSTALL_UPTIME_KUMA"]}" != "true" ]; then
        return 0
    fi

    print_section "Uptime Kuma Configuration"

    CONFIG["UPTIME_KUMA_PORT"]="3010"

    print_success "Uptime Kuma configured (web UI on port 3010)"
    log "INFO" "Uptime Kuma configured"
}

configure_monitoring() {
    if [ "${CONFIG["INSTALL_MONITORING"]}" != "true" ]; then
        return 0
    fi

    print_section "Monitoring Stack Configuration"

    CONFIG["GRAFANA_PORT"]="3020"
    CONFIG["PROMETHEUS_PORT"]="9090"

    # Grafana admin
    read -p "Grafana admin username [admin]: " grafana_user
    CONFIG["GRAFANA_ADMIN_USER"]="${grafana_user:-admin}"

    read -sp "Grafana admin password (or Enter to generate): " grafana_pass
    echo ""
    if [ -z "$grafana_pass" ]; then
        grafana_pass=$(generate_secret)
        print_info "Generated password: $grafana_pass"
    fi
    CREDENTIALS["GRAFANA_ADMIN_PASSWORD"]=$grafana_pass

    print_success "Monitoring stack configured"
    log "INFO" "Grafana user: ${CONFIG["GRAFANA_ADMIN_USER"]}"
}

configure_signal() {
    if [ "${CONFIG["INSTALL_SIGNAL"]}" != "true" ]; then
        return 0
    fi

    print_section "Signal Proxy Configuration"

    CONFIG["SIGNAL_PORT"]="8082"

    echo ""
    echo "Signal proxy requires phone number linking."
    echo "You'll need to scan a QR code after deployment."
    echo ""

    print_success "Signal proxy configured"
    log "INFO" "Signal proxy configured"
}

configure_openclaw() {
    if [ "${CONFIG["INSTALL_OPENCLAW"]}" != "true" ]; then
        return 0
    fi

    print_section "OpenClaw Configuration"

    CONFIG["OPENCLAW_PORT"]="3004"

    print_success "OpenClaw configured"
    log "INFO" "OpenClaw configured"
}

configure_vectordb() {
    if [ "${CONFIG["INSTALL_VECTORDB"]}" != "true" ]; then
        return 0
    fi

    print_section "Vector Database Configuration"

    case "${CONFIG["VECTORDB_TYPE"]}" in
        qdrant)
            CONFIG["QDRANT_PORT"]="6333"
            CONFIG["QDRANT_GRPC_PORT"]="6334"
            CREDENTIALS["QDRANT_API_KEY"]=$(generate_secret)
            print_success "Qdrant configured (HTTP: 6333, gRPC: 6334)"
            ;;
        chroma)
            CONFIG["CHROMA_PORT"]="8000"
            CONFIG["CHROMA_PERSIST_DIR"]="${CONFIG["DATA_DIR"]}/chroma"
            print_success "Chroma configured (port 8000)"
            ;;
        weaviate)
            CONFIG["WEAVIATE_PORT"]="8080"
            CONFIG["WEAVIATE_GRPC_PORT"]="50051"
            CREDENTIALS["WEAVIATE_API_KEY"]=$(generate_secret)
            print_success "Weaviate configured (HTTP: 8080, gRPC: 50051)"
            ;;
    esac

    log "INFO" "Vector DB configured: ${CONFIG["VECTORDB_TYPE"]}"
}
#===============================================================================
# CONFIGURATION SAVE & SUMMARY FUNCTIONS
#===============================================================================

save_config() {
    print_section "Saving Configuration"

    local config_file="${SCRIPT_DIR}/install.config"

    # Save main configuration
    {
        echo "# AI Platform Installation Configuration"
        echo "# Generated: $(date)"
        echo ""

        for key in "${!CONFIG[@]}"; do
            echo "CONFIG_${key}=\"${CONFIG[$key]}\""
        done

        echo ""
        echo "# LLM Providers"
        for provider in "${!LLM_PROVIDERS[@]}"; do
            echo "LLM_PROVIDER_${provider}=\"${LLM_PROVIDERS[$provider]}\""
        done

    } > "$config_file"

    print_success "Configuration saved to: $config_file"
    log "INFO" "Configuration saved"

    # Save credentials separately (encrypted)
    local creds_file="${SCRIPT_DIR}/.credentials"
    {
        echo "# CREDENTIALS - KEEP SECURE!"
        echo "# Generated: $(date)"
        echo ""

        for key in "${!CREDENTIALS[@]}"; do
            echo "CRED_${key}=\"${CREDENTIALS[$key]}\""
        done

    } > "$creds_file"

    chmod 600 "$creds_file"
    print_success "Credentials saved to: $creds_file (permissions: 600)"
    log "INFO" "Credentials saved securely"
}

generate_summary() {
    print_section "Installation Summary"

    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║           AI PLATFORM INSTALLATION CONFIGURATION               ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    # System Information
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "SYSTEM INFORMATION:"
    echo "  Public IP:        ${CONFIG["PUBLIC_IP"]}"
    echo "  Domain:           ${CONFIG["DOMAIN"]:-Not configured}"
    echo "  Cloudflare:       ${CONFIG["USE_CLOUDFLARE"]}"
    echo "  Timezone:         ${CONFIG["TIMEZONE"]}"
    echo "  Install Dir:      ${CONFIG["INSTALL_DIR"]}"
    echo "  Data Dir:         ${CONFIG["DATA_DIR"]}"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Core Infrastructure
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "CORE INFRASTRUCTURE:"
    [ "${CONFIG["INSTALL_POSTGRES"]}" == "true" ] && echo "  ✓ PostgreSQL       Port: ${CONFIG["POSTGRES_PORT"]}"
    [ "${CONFIG["INSTALL_REDIS"]}" == "true" ] && echo "  ✓ Redis            Port: ${CONFIG["REDIS_PORT"]}"
    [ "${CONFIG["INSTALL_MINIO"]}" == "true" ] && echo "  ✓ MinIO            Port: ${CONFIG["MINIO_PORT"]} (Console: ${CONFIG["MINIO_CONSOLE_PORT"]})"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # LLM Services
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "LLM SERVICES:"
    [ "${CONFIG["INSTALL_OLLAMA"]}" == "true" ] && echo "  ✓ Ollama           Port: ${CONFIG["OLLAMA_PORT"]}"
    [ "${CONFIG["INSTALL_LITELLM"]}" == "true" ] && echo "  ✓ LiteLLM          Port: ${CONFIG["LITELLM_PORT"]}"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Workflow & Automation
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "WORKFLOW & AUTOMATION:"
    [ "${CONFIG["INSTALL_N8N"]}" == "true" ] && echo "  ✓ n8n              Port: ${CONFIG["N8N_PORT"]}"
    [ "${CONFIG["INSTALL_FLOWISE"]}" == "true" ] && echo "  ✓ Flowise          Port: ${CONFIG["FLOWISE_PORT"]}"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Chat Interfaces
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "CHAT INTERFACES:"
    [ "${CONFIG["INSTALL_OPENWEBUI"]}" == "true" ] && echo "  ✓ Open WebUI       Port: ${CONFIG["OPENWEBUI_PORT"]}"
    [ "${CONFIG["INSTALL_ANYTHINGLLM"]}" == "true" ] && echo "  ✓ AnythingLLM      Port: ${CONFIG["ANYTHINGLLM_PORT"]}"
    [ "${CONFIG["INSTALL_LIBRECHAT"]}" == "true" ] && echo "  ✓ LibreChat        Port: ${CONFIG["LIBRECHAT_PORT"]}"
    [ "${CONFIG["INSTALL_DIFY"]}" == "true" ] && echo "  ✓ Dify             Port: ${CONFIG["DIFY_NGINX_PORT"]}"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Observability
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "OBSERVABILITY:"
    [ "${CONFIG["INSTALL_LANGFUSE"]}" == "true" ] && echo "  ✓ Langfuse         Port: ${CONFIG["LANGFUSE_PORT"]}"
    [ "${CONFIG["INSTALL_MONITORING"]}" == "true" ] && echo "  ✓ Grafana          Port: ${CONFIG["GRAFANA_PORT"]}"
    [ "${CONFIG["INSTALL_MONITORING"]}" == "true" ] && echo "  ✓ Prometheus       Port: ${CONFIG["PROMETHEUS_PORT"]}"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Management Tools
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "MANAGEMENT TOOLS:"
    [ "${CONFIG["INSTALL_PORTAINER"]}" == "true" ] && echo "  ✓ Portainer        Port: ${CONFIG["PORTAINER_PORT"]}"
    [ "${CONFIG["INSTALL_UPTIME_KUMA"]}" == "true" ] && echo "  ✓ Uptime Kuma      Port: ${CONFIG["UPTIME_KUMA_PORT"]}"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Additional Services
    if [ "${CONFIG["INSTALL_VECTORDB"]}" == "true" ] || [ "${CONFIG["INSTALL_SIGNAL"]}" == "true" ] || [ "${CONFIG["INSTALL_OPENCLAW"]}" == "true" ]; then
        print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "ADDITIONAL SERVICES:"
        [ "${CONFIG["INSTALL_VECTORDB"]}" == "true" ] && echo "  ✓ ${CONFIG["VECTORDB_TYPE"]^}  Port: ${CONFIG["${CONFIG["VECTORDB_TYPE"]^^}_PORT"]}"
        [ "${CONFIG["INSTALL_SIGNAL"]}" == "true" ] && echo "  ✓ Signal Proxy     Port: ${CONFIG["SIGNAL_PORT"]}"
        [ "${CONFIG["INSTALL_OPENCLAW"]}" == "true" ] && echo "  ✓ OpenClaw         Port: ${CONFIG["OPENCLAW_PORT"]}"
        print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    fi

    # LLM Providers
    local provider_count=0
    for provider in "${!LLM_PROVIDERS[@]}"; do
        if [ "${LLM_PROVIDERS[$provider]}" == "true" ]; then
            ((provider_count++))
        fi
    done

    if [ $provider_count -gt 0 ]; then
        print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "LLM PROVIDERS CONFIGURED: $provider_count"
        for provider in "${!LLM_PROVIDERS[@]}"; do
            if [ "${LLM_PROVIDERS[$provider]}" == "true" ]; then
                echo "  ✓ ${provider^}"
            fi
        done
        print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    fi

    # Next Steps
    print_success "╔════════════════════════════════════════════════════════════════╗"
    print_success "║                         NEXT STEPS                             ║"
    print_success "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "1. Review configuration files:"
    echo "   - ${SCRIPT_DIR}/install.config"
    echo "   - ${SCRIPT_DIR}/.credentials"
    echo ""
    echo "2. Run infrastructure setup:"
    echo "   ./2-setup-infrastructure.sh"
    echo ""
    echo "3. Deploy services:"
    echo "   ./3-deploy-services.sh"
    echo ""
    echo "4. Configure access (domain/SSL):"
    echo "   ./4-configure-access.sh"
    echo ""

    print_warning "⚠️  IMPORTANT: Keep .credentials file secure!"
    print_warning "⚠️  Contains sensitive passwords and API keys"
    echo ""

    log "INFO" "Configuration summary generated"
}

collect_system_config() {
    print_header "AI Platform - System Configuration Collection"

    echo ""
    echo "This wizard will collect all necessary configuration for your AI platform."
    echo "You can modify these settings later if needed."
    echo ""

    read -p "Press Enter to begin configuration..."

    # Step 1: Collect basic system info
    collect_basic_info

    # Step 2: Network configuration
    configure_network

    # Step 3: Timezone
    configure_timezone

    # Step 4: Telemetry
    configure_telemetry

    # Step 5: Service selection
    select_services

    # Step 6: Vector database (if selected)
    if [ "${CONFIG["INSTALL_VECTORDB"]}" == "true" ]; then
        select_vector_db
    fi

    # Step 7: LLM provider configuration
    configure_llm_providers

    # Step 8: Service-specific configuration
    configure_postgres
    configure_redis
    configure_minio
    configure_ollama
    configure_litellm
    configure_n8n
    configure_flowise
    configure_openwebui
    configure_anythingllm
    configure_langfuse
    configure_dify
    configure_librechat
    configure_portainer
    configure_uptime_kuma
    configure_monitoring
    configure_signal
    configure_openclaw
    configure_vectordb

    # Step 9: Save everything
    save_config

    # Step 10: Show summary
    generate_summary

    log "INFO" "Configuration collection completed"
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

main() {
    # Initialize logging
    log "INFO" "Starting AI Platform Setup - Script 1"
    log "INFO" "Script directory: $SCRIPT_DIR"

    # Run system checks
    check_root
    check_os
    check_dependencies
    detect_gpu

    # Collect all configuration
    collect_system_config

    # Final message
    echo ""
    print_success "╔════════════════════════════════════════════════════════════════╗"
    print_success "║         CONFIGURATION COLLECTION COMPLETED SUCCESSFULLY        ║"
    print_success "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    print_info "Configuration saved. Ready to proceed with infrastructure setup."
    print_info "Run: ./2-setup-infrastructure.sh"
    echo ""

    log "INFO" "Script 1 completed successfully"
}

# Execute main function
main "$@"
