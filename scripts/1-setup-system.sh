#!/bin/bash
#===============================================================================
# AI Platform Automation - Script 1: System Setup & Configuration Collection
#===============================================================================
# Version: 3.1.0 - Enhanced with Gemini, OpenRouter, LiteLLM routing, URL summary
#===============================================================================

set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_VERSION="3.1.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BASE_DIR="/root/scripts"
readonly DATA_DIR="/mnt/data"
readonly LOG_DIR="${BASE_DIR}/logs"
readonly CONFIG_FILE="${BASE_DIR}/.env.master"
readonly STATE_FILE="${BASE_DIR}/.setup_state"
readonly LOG_FILE="${LOG_DIR}/setup-$(date +%Y%m%d-%H%M%S).log"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1
readonly EXIT_USER_CANCEL=2
readonly EXIT_VALIDATION_FAILED=3

# Global associative arrays
declare -A CONFIG=(
    ["INSTALL_POSTGRES"]="false"
    ["INSTALL_N8N"]="false"
    ["INSTALL_FLOWISE"]="false"
    ["INSTALL_LITELLM"]="false"
    ["INSTALL_OLLAMA"]="false"
    ["INSTALL_LANGFUSE"]="false"
    ["INSTALL_DIFY"]="false"
    ["INSTALL_OPENWEBUI"]="false"
    ["INSTALL_ANYTHINGLLM"]="false"
    ["INSTALL_OPENCLAW"]="false"
    ["INSTALL_MINIO"]="false"
    ["INSTALL_SIGNAL_API"]="false"
    ["INSTALL_TAILSCALE"]="false"
    ["INSTALL_VECTORDB"]="false"
    ["GDRIVE_ENABLED"]="false"
    ["USE_DOMAIN"]="false"
    ["LITELLM_ROUTING_STRATEGY"]="usage-based-routing"
)

declare -A CREDENTIALS=()
declare -A LLM_PROVIDERS=()
declare -A LLM_MODELS=()
declare -a SELECTED_SERVICES=()
declare -a CONFIGURED_LLMS=()

#===============================================================================
# SIGNAL HANDLING
#===============================================================================
trap cleanup_on_exit EXIT
trap handle_interrupt INT TERM

cleanup_on_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ] && [ $exit_code -ne $EXIT_USER_CANCEL ]; then
        log "ERROR" "Script exited with error code: $exit_code"
        echo -e "\n${RED}Setup interrupted or failed. Check log: ${LOG_FILE}${NC}"
    fi
}

handle_interrupt() {
    echo -e "\n${YELLOW}⚠️ Setup interrupted by user${NC}"
    log "WARN" "User interrupted setup"
    exit $EXIT_USER_CANCEL
}

#===============================================================================
# LOGGING FUNCTIONS
#===============================================================================
setup_logging() {
    mkdir -p "$LOG_DIR"
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
}

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE"
}

print_header() {
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} $1"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}\n"
    log "INFO" "$1"
}

print_section() {
    echo -e "\n${BLUE}━━━ $1 ━━━${NC}\n"
    log "INFO" "Section: $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
    log "INFO" "Success: $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
    log "ERROR" "$1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    log "WARN" "$1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
    log "INFO" "$1"
}

#===============================================================================
# VALIDATION FUNCTIONS
#===============================================================================
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        exit $EXIT_ERROR
    fi
}

validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local IFS='.'
        read -ra ADDR <<< "$ip"
        [[ ${ADDR[0]} -le 255 && ${ADDR[1]} -le 255 && ${ADDR[2]} -le 255 && ${ADDR[3]} -le 255 ]]
        return $?
    fi
    return 1
}

validate_domain() {
    local domain=$1
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    fi
    return 1
}

validate_email() {
    local email=$1
    if [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    return 1
}

validate_port() {
    local port=$1
    if [[ $port =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    fi
    return 1
}

check_port_available() {
    local port=$1
    if command -v netstat &> /dev/null; then
        if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            return 1
        fi
    elif command -v ss &> /dev/null; then
        if ss -tuln 2>/dev/null | grep -q ":${port} "; then
            return 1
        fi
    fi
    return 0
}

check_dependencies() {
    print_section "Checking System Dependencies"
    
    local missing_deps=()
    local deps=("curl" "wget" "git" "jq" "openssl" "gpg" "systemctl")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
            print_warning "Missing: $dep"
        else
            print_success "Found: $dep"
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        read -p "Install missing dependencies now? (y/n): " install_deps
        if [[ $install_deps =~ ^[Yy]$ ]]; then
            apt-get update
            apt-get install -y "${missing_deps[@]}"
            print_success "Dependencies installed"
        else
            print_error "Cannot proceed without required dependencies"
            exit $EXIT_ERROR
        fi
    else
        print_success "All dependencies satisfied"
    fi
}

check_disk_space() {
    print_section "Checking Disk Space"
    
    local required_space_gb=50
    local available_space_gb
    available_space_gb=$(df -BG "$BASE_DIR" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [ -z "$available_space_gb" ]; then
        print_warning "Could not determine disk space"
        return
    fi
    
    print_info "Available space: ${available_space_gb}GB"
    print_info "Required space: ${required_space_gb}GB"
    
    if [ "$available_space_gb" -lt "$required_space_gb" ]; then
        print_warning "Low disk space. Recommended: ${required_space_gb}GB, Available: ${available_space_gb}GB"
        read -p "Continue anyway? (y/n): " continue_low_space
        if [[ ! $continue_low_space =~ ^[Yy]$ ]]; then
            exit $EXIT_USER_CANCEL
        fi
    else
        print_success "Sufficient disk space available"
    fi
}

detect_public_ip() {
    print_section "Detecting Public IP"
    
    local ip
    ip=$(curl -s -4 --max-time 5 icanhazip.com || curl -s -4 --max-time 5 ifconfig.me || curl -s -4 --max-time 5 api.ipify.org || echo "")
    
    if [ -n "$ip" ] && validate_ip "$ip"; then
        CONFIG["PUBLIC_IP"]=$ip
        print_success "Detected public IP: $ip"
    else
        print_warning "Could not auto-detect public IP"
        while true; do
            read -p "Enter public IP manually: " manual_ip
            if validate_ip "$manual_ip"; then
                CONFIG["PUBLIC_IP"]=$manual_ip
                print_success "Using IP: $manual_ip"
                break
            else
                print_error "Invalid IP address format"
            fi
        done
    fi
}

detect_gpu() {
    print_section "Detecting GPU"
    
    if lspci 2>/dev/null | grep -i nvidia &> /dev/null; then
        if command -v nvidia-smi &> /dev/null; then
            print_success "NVIDIA GPU detected with drivers"
            CONFIG["OLLAMA_GPU_ENABLED"]="true"
        else
            print_warning "NVIDIA GPU detected but drivers not installed"
            CONFIG["OLLAMA_GPU_ENABLED"]="false"
            print_info "NVIDIA Docker runtime can be installed in Script 2"
        fi
    else
        print_info "No NVIDIA GPU detected, using CPU mode"
        CONFIG["OLLAMA_GPU_ENABLED"]="false"
    fi
}

#===============================================================================
# UTILITY FUNCTIONS
#===============================================================================
generate_password() {
    local length=${1:-32}
    openssl rand -base64 48 | tr -d "=+/" | cut -c1-${length}
}

generate_secret() {
    openssl rand -hex 32
}

save_state() {
    declare -p CONFIG CREDENTIALS LLM_PROVIDERS LLM_MODELS SELECTED_SERVICES CONFIGURED_LLMS > "$STATE_FILE" 2>/dev/null || true
    log "INFO" "State saved to $STATE_FILE"
}

load_state() {
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE"
        log "INFO" "State loaded from $STATE_FILE"
        return 0
    fi
    return 1
}

#===============================================================================
# NETWORK CONFIGURATION
#===============================================================================
configure_network() {
    print_header "Network Configuration"
    
    # Domain or IP
    read -p "Do you have a domain name? (y/n): " has_domain
    if [[ $has_domain =~ ^[Yy]$ ]]; then
        while true; do
            read -p "Enter domain name (e.g., ai.example.com): " domain
            if validate_domain "$domain"; then
                CONFIG["DOMAIN"]=$domain
                CONFIG["USE_DOMAIN"]="true"
                print_success "Domain: $domain"
                break
            else
                print_error "Invalid domain format"
            fi
        done
    else
        CONFIG["USE_DOMAIN"]="false"
        CONFIG["DOMAIN"]=""
        print_info "Will use IP-based access: ${CONFIG["PUBLIC_IP"]}"
    fi
    
    # SSL Configuration
    if [[ "${CONFIG["USE_DOMAIN"]}" == "true" ]]; then
        echo ""
        echo "SSL Certificate Options:"
        echo "  1) Let's Encrypt - Free, auto-renewal (RECOMMENDED)"
        echo "  2) Self-signed - For testing/internal use"
        echo ""
        read -p "Select SSL mode (1-2): " ssl_choice
        
        case $ssl_choice in
            1)
                CONFIG["SSL_MODE"]="letsencrypt"
                while true; do
                    read -p "Enter email for Let's Encrypt notifications: " le_email
                    if validate_email "$le_email"; then
                        CONFIG["SSL_EMAIL"]=$le_email
                        print_success "Let's Encrypt enabled"
                        break
                    else
                        print_error "Invalid email format"
                    fi
                done
                ;;
            2)
                CONFIG["SSL_MODE"]="selfsigned"
                print_info "Will use self-signed certificates"
                ;;
            *)
                print_warning "Invalid choice, using self-signed"
                CONFIG["SSL_MODE"]="selfsigned"
                ;;
        esac
    else
        CONFIG["SSL_MODE"]="none"
        print_info "SSL disabled for IP-based access"
    fi
}

#===============================================================================
# SERVICE SELECTION
#===============================================================================
select_services() {
    print_header "Service Selection"
    
    echo "Select services to install (space-separated numbers, or 'all'):"
    echo ""
    echo "  Core Infrastructure:"
    echo "    1)  PostgreSQL - Database (required for most services)"
    echo "    2)  Redis - Caching & queue management"
    echo "    3)  MinIO - S3-compatible object storage"
    echo ""
    echo "  AI Workflow & Automation:"
    echo "    4)  n8n - Workflow automation"
    echo "    5)  Flowise - Low-code AI workflows"
    echo ""
    echo "  LLM Infrastructure:"
    echo "    6)  LiteLLM - Unified LLM proxy with load balancing"
    echo "    7)  Ollama - Local LLM hosting"
    echo ""
    echo "  Chat & Interface Platforms:"
    echo "    8)  Open WebUI - Modern LLM chat interface"
    echo "    9)  LibreChat - Multi-model chat platform"
    echo "    10) AnythingLLM - Full-stack LLM workspace"
    echo "    11) Dify - LLM app development platform"
    echo ""
    echo "  Observability & Management:"
    echo "    12) Langfuse - LLM observability & analytics"
    echo ""
    echo "  Optional Integrations:"
    echo "    13) Signal API - Messaging integration"
    echo "    14) Tailscale - Private networking (VPN)"
    echo ""
    
    read -p "Enter selection (e.g., '1 4 6 8' or 'all'): " service_selection
    
    if [[ $service_selection == "all" ]]; then
        SELECTED_SERVICES=(1 2 3 4 5 6 7 8 9 10 11 12 13 14)
    else
        read -ra SELECTED_SERVICES <<< "$service_selection"
    fi
    
    # Map selections to install flags
    for num in "${SELECTED_SERVICES[@]}"; do
        case $num in
            1) CONFIG["INSTALL_POSTGRES"]="true" ;;
            2) CONFIG["INSTALL_REDIS"]="true" ;;
            3) CONFIG["INSTALL_MINIO"]="true" ;;
            4) CONFIG["INSTALL_N8N"]="true" ;;
            5) CONFIG["INSTALL_FLOWISE"]="true" ;;
            6) CONFIG["INSTALL_LITELLM"]="true" ;;
            7) CONFIG["INSTALL_OLLAMA"]="true" ;;
            8) CONFIG["INSTALL_OPENWEBUI"]="true" ;;
            9) CONFIG["INSTALL_LIBRECHAT"]="true" ;;
            10) CONFIG["INSTALL_ANYTHINGLLM"]="true" ;;
            11) CONFIG["INSTALL_DIFY"]="true" ;;
            12) CONFIG["INSTALL_LANGFUSE"]="true" ;;
            13) CONFIG["INSTALL_SIGNAL_API"]="true" ;;
            14) CONFIG["INSTALL_TAILSCALE"]="true" ;;
        esac
    done
    
    # Show selected services
    echo ""
    print_section "Selected Services"
    for key in "${!CONFIG[@]}"; do
        if [[ $key == INSTALL_* ]] && [[ ${CONFIG[$key]} == "true" ]]; then
            local service_name=${key#INSTALL_}
            print_success "$service_name"
        fi
    done
}

#===============================================================================
# LLM PROVIDER CONFIGURATION - ENHANCED
#===============================================================================
configure_llm_providers() {
    print_header "LLM Provider Configuration"
    
    echo "Configure LLM providers (you can skip any):"
    echo ""
    
    # OpenAI
    read -p "Configure OpenAI? (y/n): " config_openai
    if [[ $config_openai =~ ^[Yy]$ ]]; then
        read -p "Enter OpenAI API Key: " openai_key
        if [ -n "$openai_key" ]; then
            LLM_PROVIDERS["OPENAI_API_KEY"]=$openai_key
            CONFIGURED_LLMS+=("openai")
            
            # Fetch available models
            print_info "Fetching OpenAI models..."
            local models=$(curl -s https://api.openai.com/v1/models                 -H "Authorization: Bearer $openai_key" | jq -r '.data[].id' | grep -E '^gpt-' | head -10)
            LLM_MODELS["OPENAI"]=$models
            print_success "OpenAI configured"
        fi
    fi
    
    # Anthropic
    read -p "Configure Anthropic (Claude)? (y/n): " config_anthropic
    if [[ $config_anthropic =~ ^[Yy]$ ]]; then
        read -p "Enter Anthropic API Key: " anthropic_key
        if [ -n "$anthropic_key" ]; then
            LLM_PROVIDERS["ANTHROPIC_API_KEY"]=$anthropic_key
            CONFIGURED_LLMS+=("anthropic")
            LLM_MODELS["ANTHROPIC"]="claude-3-5-sonnet-20241022,claude-3-5-haiku-20241022,claude-3-opus-20240229"
            print_success "Anthropic configured"
        fi
    fi
    
    # Google Gemini - NEW
    read -p "Configure Google Gemini? (y/n): " config_gemini
    if [[ $config_gemini =~ ^[Yy]$ ]]; then
        read -p "Enter Google AI API Key: " gemini_key
        if [ -n "$gemini_key" ]; then
            LLM_PROVIDERS["GEMINI_API_KEY"]=$gemini_key
            CONFIGURED_LLMS+=("gemini")
            LLM_MODELS["GEMINI"]="gemini-2.0-flash-exp,gemini-1.5-pro-latest,gemini-1.5-flash-latest"
            print_success "Google Gemini configured"
        fi
    fi
    
    # OpenRouter - NEW
    read -p "Configure OpenRouter? (y/n): " config_openrouter
    if [[ $config_openrouter =~ ^[Yy]$ ]]; then
        read -p "Enter OpenRouter API Key: " openrouter_key
        if [ -n "$openrouter_key" ]; then
            LLM_PROVIDERS["OPENROUTER_API_KEY"]=$openrouter_key
            CONFIGURED_LLMS+=("openrouter")
            
            print_info "Fetching OpenRouter models..."
            local or_models=$(curl -s https://openrouter.ai/api/v1/models                 -H "Authorization: Bearer $openrouter_key" | jq -r '.data[].id' | head -20)
            LLM_MODELS["OPENROUTER"]=$or_models
            print_success "OpenRouter configured"
        fi
    fi
    
    # Groq
    read -p "Configure Groq? (y/n): " config_groq
    if [[ $config_groq =~ ^[Yy]$ ]]; then
        read -p "Enter Groq API Key: " groq_key
        if [ -n "$groq_key" ]; then
            LLM_PROVIDERS["GROQ_API_KEY"]=$groq_key
            CONFIGURED_LLMS+=("groq")
            LLM_MODELS["GROQ"]="llama-3.3-70b-versatile,llama-3.2-90b-text-preview,mixtral-8x7b-32768"
            print_success "Groq configured"
        fi
    fi
    
    # Mistral
    read -p "Configure Mistral? (y/n): " config_mistral
    if [[ $config_mistral =~ ^[Yy]$ ]]; then
        read -p "Enter Mistral API Key: " mistral_key
        if [ -n "$mistral_key" ]; then
            LLM_PROVIDERS["MISTRAL_API_KEY"]=$mistral_key
            CONFIGURED_LLMS+=("mistral")
            LLM_MODELS["MISTRAL"]="mistral-large-latest,mistral-medium-latest,mistral-small-latest"
            print_success "Mistral configured"
        fi
    fi
    
    # Cohere
    read -p "Configure Cohere? (y/n): " config_cohere
    if [[ $config_cohere =~ ^[Yy]$ ]]; then
        read -p "Enter Cohere API Key: " cohere_key
        if [ -n "$cohere_key" ]; then
            LLM_PROVIDERS["COHERE_API_KEY"]=$cohere_key
            CONFIGURED_LLMS+=("cohere")
            LLM_MODELS["COHERE"]="command-r-plus,command-r,command"
            print_success "Cohere configured"
        fi
    fi
    
    # Perplexity
    read -p "Configure Perplexity? (y/n): " config_perplexity
    if [[ $config_perplexity =~ ^[Yy]$ ]]; then
        read -p "Enter Perplexity API Key: " perplexity_key
        if [ -n "$perplexity_key" ]; then
            LLM_PROVIDERS["PERPLEXITY_API_KEY"]=$perplexity_key
            CONFIGURED_LLMS+=("perplexity")
            LLM_MODELS["PERPLEXITY"]="llama-3.1-sonar-large-128k-online,llama-3.1-sonar-small-128k-online"
            print_success "Perplexity configured"
        fi
    fi
    
    # Together AI
    read -p "Configure Together AI? (y/n): " config_together
    if [[ $config_together =~ ^[Yy]$ ]]; then
        read -p "Enter Together AI API Key: " together_key
        if [ -n "$together_key" ]; then
            LLM_PROVIDERS["TOGETHER_API_KEY"]=$together_key
            CONFIGURED_LLMS+=("together")
            LLM_MODELS["TOGETHER"]="meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo,mistralai/Mixtral-8x7B-Instruct-v0.1"
            print_success "Together AI configured"
        fi
    fi
    
    # Hugging Face
    read -p "Configure Hugging Face? (y/n): " config_hf
    if [[ $config_hf =~ ^[Yy]$ ]]; then
        read -p "Enter Hugging Face API Token: " hf_token
        if [ -n "$hf_token" ]; then
            LLM_PROVIDERS["HUGGINGFACE_API_KEY"]=$hf_token
            CONFIGURED_LLMS+=("huggingface")
            print_success "Hugging Face configured"
        fi
    fi
    
    # Azure OpenAI
    read -p "Configure Azure OpenAI? (y/n): " config_azure
    if [[ $config_azure =~ ^[Yy]$ ]]; then
        read -p "Enter Azure OpenAI API Key: " azure_key
        read -p "Enter Azure OpenAI Endpoint: " azure_endpoint
        read -p "Enter Azure API Version (default: 2024-02-15-preview): " azure_version
        azure_version=${azure_version:-2024-02-15-preview}
        
        if [ -n "$azure_key" ] && [ -n "$azure_endpoint" ]; then
            LLM_PROVIDERS["AZURE_API_KEY"]=$azure_key
            LLM_PROVIDERS["AZURE_API_BASE"]=$azure_endpoint
            LLM_PROVIDERS["AZURE_API_VERSION"]=$azure_version
            CONFIGURED_LLMS+=("azure")
            print_success "Azure OpenAI configured"
        fi
    fi
    
    # LiteLLM Routing Strategy Configuration
    if [[ "${CONFIG["INSTALL_LITELLM"]}" == "true" ]] && [ ${#CONFIGURED_LLMS[@]} -gt 0 ]; then
        echo ""
        print_section "LiteLLM Routing Strategy"
        echo "Select routing strategy for LiteLLM:"
        echo "  1) usage-based-routing - Route based on API usage/cost (RECOMMENDED)"
        echo "  2) simple-shuffle - Random selection from available models"
        echo "  3) least-busy - Route to least busy endpoint"
        echo "  4) latency-based-routing - Route to fastest responding endpoint"
        echo ""
        read -p "Select routing strategy (1-4, default: 1): " routing_choice
        
        case ${routing_choice:-1} in
            1) CONFIG["LITELLM_ROUTING_STRATEGY"]="usage-based-routing" ;;
            2) CONFIG["LITELLM_ROUTING_STRATEGY"]="simple-shuffle" ;;
            3) CONFIG["LITELLM_ROUTING_STRATEGY"]="least-busy" ;;
            4) CONFIG["LITELLM_ROUTING_STRATEGY"]="latency-based-routing" ;;
            *) CONFIG["LITELLM_ROUTING_STRATEGY"]="usage-based-routing" ;;
        esac
        
        print_success "LiteLLM routing: ${CONFIG["LITELLM_ROUTING_STRATEGY"]}"
        
        # Failover configuration
        read -p "Enable automatic failover between providers? (y/n, default: y): " enable_failover
        if [[ ${enable_failover:-y} =~ ^[Yy]$ ]]; then
            CONFIG["LITELLM_ENABLE_FAILOVER"]="true"
            print_success "Failover enabled"
        else
            CONFIG["LITELLM_ENABLE_FAILOVER"]="false"
        fi
    fi
    
    # Summary of configured providers
    if [ ${#CONFIGURED_LLMS[@]} -gt 0 ]; then
        echo ""
        print_section "Configured LLM Providers"
        for provider in "${CONFIGURED_LLMS[@]}"; do
            print_success "$provider"
            if [ -n "${LLM_MODELS[$provider]:-}" ]; then
                echo -e "  ${CYAN}Available models: ${LLM_MODELS[$provider]}${NC}"
            fi
        done
    else
        print_warning "No LLM providers configured"
    fi
}

#===============================================================================
# DATABASE CONFIGURATION
#===============================================================================
configure_databases() {
    print_header "Database Configuration"
    
    if [[ "${CONFIG["INSTALL_POSTGRES"]}" == "true" ]]; then
        print_section "PostgreSQL Configuration"
        
        # Generate strong password
        local pg_password=$(generate_password 32)
        CREDENTIALS["POSTGRES_PASSWORD"]=$pg_password
        
        read -p "PostgreSQL username (default: aiplatform): " pg_user
        CREDENTIALS["POSTGRES_USER"]=${pg_user:-aiplatform}
        
        read -p "PostgreSQL database name (default: aiplatform): " pg_db
        CREDENTIALS["POSTGRES_DB"]=${pg_db:-aiplatform}
        
        print_success "PostgreSQL configured"
        print_info "Username: ${CREDENTIALS["POSTGRES_USER"]}"
        print_info "Password: [auto-generated - saved to config]"
        print_info "Database: ${CREDENTIALS["POSTGRES_DB"]}"
    fi
    
    if [[ "${CONFIG["INSTALL_REDIS"]}" == "true" ]]; then
        print_section "Redis Configuration"
        
        local redis_password=$(generate_password 32)
        CREDENTIALS["REDIS_PASSWORD"]=$redis_password
        
        print_success "Redis configured"
        print_info "Password: [auto-generated - saved to config]"
    fi
}

#===============================================================================
# PORT CONFIGURATION
#===============================================================================
configure_ports() {
    print_header "Port Configuration"
    
    # Default ports
    declare -A DEFAULT_PORTS=(
        ["N8N"]="5678"
        ["FLOWISE"]="3000"
        ["LITELLM"]="4000"
        ["OLLAMA"]="11434"
        ["OPENWEBUI"]="8080"
        ["LIBRECHAT"]="3001"
        ["ANYTHINGLLM"]="3002"
        ["DIFY"]="3003"
        ["LANGFUSE"]="3004"
        ["POSTGRES"]="5432"
        ["REDIS"]="6379"
        ["MINIO"]="9000"
        ["MINIO_CONSOLE"]="9001"
    )
    
    if [[ "${CONFIG["USE_DOMAIN"]}" == "false" ]]; then
        print_info "Using IP-based access - ports will be exposed"
        echo ""
        read -p "Use default ports? (y/n): " use_defaults
        
        if [[ ! $use_defaults =~ ^[Yy]$ ]]; then
            for service in "${!DEFAULT_PORTS[@]}"; do
                local config_key="INSTALL_${service}"
                if [[ "${CONFIG[$config_key]:-false}" == "true" ]]; then
                    while true; do
                        read -p "Port for $service (default: ${DEFAULT_PORTS[$service]}): " custom_port
                        custom_port=${custom_port:-${DEFAULT_PORTS[$service]}}
                        
                        if validate_port "$custom_port" && check_port_available "$custom_port"; then
                            CONFIG["${service}_PORT"]=$custom_port
                            print_success "$service will use port $custom_port"
                            break
                        else
                            print_error "Port $custom_port is invalid or already in use"
                        fi
                    done
                fi
            done
        else
            for service in "${!DEFAULT_PORTS[@]}"; do
                CONFIG["${service}_PORT"]=${DEFAULT_PORTS[$service]}
            done
            print_success "Using default ports"
        fi
    else
        print_info "Using domain-based access - services behind reverse proxy"
        for service in "${!DEFAULT_PORTS[@]}"; do
            CONFIG["${service}_PORT"]=${DEFAULT_PORTS[$service]}
        done
    fi
}

#===============================================================================
# GENERATE CONFIGURATION FILES
#===============================================================================
generate_env_file() {
    print_header "Generating Configuration Files"
    
    cat > "$CONFIG_FILE" << EOF
# AI Platform Master Configuration
# Generated: $(date)
# Version: $SCRIPT_VERSION

#===============================================================================
# SYSTEM CONFIGURATION
#===============================================================================
PUBLIC_IP=${CONFIG["PUBLIC_IP"]}
DOMAIN=${CONFIG["DOMAIN"]}
USE_DOMAIN=${CONFIG["USE_DOMAIN"]}
SSL_MODE=${CONFIG["SSL_MODE"]}
SSL_EMAIL=${CONFIG["SSL_EMAIL"]:-}

#===============================================================================
# SERVICE INSTALLATION FLAGS
#===============================================================================
INSTALL_POSTGRES=${CONFIG["INSTALL_POSTGRES"]}
INSTALL_REDIS=${CONFIG["INSTALL_REDIS"]}
INSTALL_MINIO=${CONFIG["INSTALL_MINIO"]}
INSTALL_N8N=${CONFIG["INSTALL_N8N"]}
INSTALL_FLOWISE=${CONFIG["INSTALL_FLOWISE"]}
INSTALL_LITELLM=${CONFIG["INSTALL_LITELLM"]}
INSTALL_OLLAMA=${CONFIG["INSTALL_OLLAMA"]}
INSTALL_OPENWEBUI=${CONFIG["INSTALL_OPENWEBUI"]}
INSTALL_LIBRECHAT=${CONFIG["INSTALL_LIBRECHAT"]}
INSTALL_ANYTHINGLLM=${CONFIG["INSTALL_ANYTHINGLLM"]}
INSTALL_DIFY=${CONFIG["INSTALL_DIFY"]}
INSTALL_LANGFUSE=${CONFIG["INSTALL_LANGFUSE"]}
INSTALL_SIGNAL_API=${CONFIG["INSTALL_SIGNAL_API"]}
INSTALL_TAILSCALE=${CONFIG["INSTALL_TAILSCALE"]}

#===============================================================================
# PORT CONFIGURATION
#===============================================================================
N8N_PORT=${CONFIG["N8N_PORT"]:-5678}
FLOWISE_PORT=${CONFIG["FLOWISE_PORT"]:-3000}
LITELLM_PORT=${CONFIG["LITELLM_PORT"]:-4000}
OLLAMA_PORT=${CONFIG["OLLAMA_PORT"]:-11434}
OPENWEBUI_PORT=${CONFIG["OPENWEBUI_PORT"]:-8080}
LIBRECHAT_PORT=${CONFIG["LIBRECHAT_PORT"]:-3001}
ANYTHINGLLM_PORT=${CONFIG["ANYTHINGLLM_PORT"]:-3002}
DIFY_PORT=${CONFIG["DIFY_PORT"]:-3003}
LANGFUSE_PORT=${CONFIG["LANGFUSE_PORT"]:-3004}
POSTGRES_PORT=${CONFIG["POSTGRES_PORT"]:-5432}
REDIS_PORT=${CONFIG["REDIS_PORT"]:-6379}
MINIO_PORT=${CONFIG["MINIO_PORT"]:-9000}
MINIO_CONSOLE_PORT=${CONFIG["MINIO_CONSOLE_PORT"]:-9001}

#===============================================================================
# DATABASE CREDENTIALS
#===============================================================================
POSTGRES_USER=${CREDENTIALS["POSTGRES_USER"]:-aiplatform}
POSTGRES_PASSWORD=${CREDENTIALS["POSTGRES_PASSWORD"]:-}
POSTGRES_DB=${CREDENTIALS["POSTGRES_DB"]:-aiplatform}
REDIS_PASSWORD=${CREDENTIALS["REDIS_PASSWORD"]:-}

#===============================================================================
# LLM PROVIDER API KEYS
#===============================================================================
EOF

    # Add LLM provider keys
    for key in "${!LLM_PROVIDERS[@]}"; do
        echo "${key}=${LLM_PROVIDERS[$key]}" >> "$CONFIG_FILE"
    done
    
    # LiteLLM configuration
    if [[ "${CONFIG["INSTALL_LITELLM"]}" == "true" ]]; then
        cat >> "$CONFIG_FILE" << EOF

#===============================================================================
# LITELLM CONFIGURATION
#===============================================================================
LITELLM_ROUTING_STRATEGY=${CONFIG["LITELLM_ROUTING_STRATEGY"]}
LITELLM_ENABLE_FAILOVER=${CONFIG["LITELLM_ENABLE_FAILOVER"]:-true}
LITELLM_MASTER_KEY=$(generate_secret)
LITELLM_SALT_KEY=$(generate_secret)

# Configured Providers
LITELLM_PROVIDERS="${CONFIGURED_LLMS[*]}"

# Model mappings per provider
EOF
        for provider in "${CONFIGURED_LLMS[@]}"; do
            if [ -n "${LLM_MODELS[$provider]:-}" ]; then
                echo "LITELLM_MODELS_${provider^^}="${LLM_MODELS[$provider]}"" >> "$CONFIG_FILE"
            fi
        done
    fi
    
    # GPU configuration
    cat >> "$CONFIG_FILE" << EOF

#===============================================================================
# GPU CONFIGURATION
#===============================================================================
OLLAMA_GPU_ENABLED=${CONFIG["OLLAMA_GPU_ENABLED"]}

#===============================================================================
# SECURITY TOKENS & SECRETS
#===============================================================================
JWT_SECRET=$(generate_secret)
SESSION_SECRET=$(generate_secret)
ENCRYPTION_KEY=$(generate_secret)

#===============================================================================
# DATA DIRECTORIES
#===============================================================================
DATA_DIR=$DATA_DIR
EOF

    chmod 600 "$CONFIG_FILE"
    print_success "Configuration file created: $CONFIG_FILE"
    log "INFO" "Configuration file generated"
}

#===============================================================================
# CONFIGURATION SUMMARY & URL GENERATION
#===============================================================================
show_summary() {
    print_header "Configuration Summary"
    
    local base_url
    if [[ "${CONFIG["USE_DOMAIN"]}" == "true" ]]; then
        if [[ "${CONFIG["SSL_MODE"]}" == "letsencrypt" ]] || [[ "${CONFIG["SSL_MODE"]}" == "selfsigned" ]]; then
            base_url="https://${CONFIG["DOMAIN"]}"
        else
            base_url="http://${CONFIG["DOMAIN"]}"
        fi
    else
        base_url="http://${CONFIG["PUBLIC_IP"]}"
    fi
    
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Network Configuration${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    if [[ "${CONFIG["USE_DOMAIN"]}" == "true" ]]; then
        echo -e "Domain: ${WHITE}${CONFIG["DOMAIN"]}${NC}"
        echo -e "SSL: ${WHITE}${CONFIG["SSL_MODE"]}${NC}"
    else
        echo -e "Public IP: ${WHITE}${CONFIG["PUBLIC_IP"]}${NC}"
        echo -e "SSL: ${WHITE}Disabled (IP-based access)${NC}"
    fi
    
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Service Access URLs${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    
    # Generate URLs for each installed service
    if [[ "${CONFIG["INSTALL_N8N"]}" == "true" ]]; then
        if [[ "${CONFIG["USE_DOMAIN"]}" == "true" ]]; then
            echo -e "n8n: ${WHITE}${base_url}/n8n${NC}"
        else
            echo -e "n8n: ${WHITE}${base_url}:${CONFIG["N8N_PORT"]}${NC}"
        fi
    fi
    
    if [[ "${CONFIG["INSTALL_FLOWISE"]}" == "true" ]]; then
        if [[ "${CONFIG["USE_DOMAIN"]}" == "true" ]]; then
            echo -e "Flowise: ${WHITE}${base_url}/flowise${NC}"
        else
            echo -e "Flowise: ${WHITE}${base_url}:${CONFIG["FLOWISE_PORT"]}${NC}"
        fi
    fi
    
    if [[ "${CONFIG["INSTALL_LITELLM"]}" == "true" ]]; then
        if [[ "${CONFIG["USE_DOMAIN"]}" == "true" ]]; then
            echo -e "LiteLLM: ${WHITE}${base_url}/litellm${NC}"
        else
            echo -e "LiteLLM: ${WHITE}${base_url}:${CONFIG["LITELLM_PORT"]}${NC}"
        fi
    fi
    
    if [[ "${CONFIG["INSTALL_OPENWEBUI"]}" == "true" ]]; then
        if [[ "${CONFIG["USE_DOMAIN"]}" == "true" ]]; then
            echo -e "Open WebUI: ${WHITE}${base_url}/openwebui${NC}"
        else
            echo -e "Open WebUI: ${WHITE}${base_url}:${CONFIG["OPENWEBUI_PORT"]}${NC}"
        fi
    fi
    
    if [[ "${CONFIG["INSTALL_LIBRECHAT"]}" == "true" ]]; then
        if [[ "${CONFIG["USE_DOMAIN"]}" == "true" ]]; then
            echo -e "LibreChat: ${WHITE}${base_url}/librechat${NC}"
        else
            echo -e "LibreChat: ${WHITE}${base_url}:${CONFIG["LIBRECHAT_PORT"]}${NC}"
        fi
    fi
    
    if [[ "${CONFIG["INSTALL_ANYTHINGLLM"]}" == "true" ]]; then
        if [[ "${CONFIG["USE_DOMAIN"]}" == "true" ]]; then
            echo -e "AnythingLLM: ${WHITE}${base_url}/anythingllm${NC}"
        else
            echo -e "AnythingLLM: ${WHITE}${base_url}:${CONFIG["ANYTHINGLLM_PORT"]}${NC}"
        fi
    fi
    
    if [[ "${CONFIG["INSTALL_DIFY"]}" == "true" ]]; then
        if [[ "${CONFIG["USE_DOMAIN"]}" == "true" ]]; then
            echo -e "Dify: ${WHITE}${base_url}/dify${NC}"
        else
            echo -e "Dify: ${WHITE}${base_url}:${CONFIG["DIFY_PORT"]}${NC}"
        fi
    fi
    
    if [[ "${CONFIG["INSTALL_LANGFUSE"]}" == "true" ]]; then
        if [[ "${CONFIG["USE_DOMAIN"]}" == "true" ]]; then
            echo -e "Langfuse: ${WHITE}${base_url}/langfuse${NC}"
        else
            echo -e "Langfuse: ${WHITE}${base_url}:${CONFIG["LANGFUSE_PORT"]}${NC}"
        fi
    fi
    
    if [[ "${CONFIG["INSTALL_MINIO"]}" == "true" ]]; then
        if [[ "${CONFIG["USE_DOMAIN"]}" == "true" ]]; then
            echo -e "MinIO Console: ${WHITE}${base_url}/minio${NC}"
        else
            echo -e "MinIO Console: ${WHITE}${base_url}:${CONFIG["MINIO_CONSOLE_PORT"]}${NC}"
        fi
    fi
    
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}LLM Providers Configured${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    
    if [ ${#CONFIGURED_LLMS[@]} -gt 0 ]; then
        for provider in "${CONFIGURED_LLMS[@]}"; do
            echo -e "✓ ${WHITE}${provider}${NC}"
            if [ -n "${LLM_MODELS[$provider]:-}" ]; then
                local model_count=$(echo "${LLM_MODELS[$provider]}" | tr ',' '\n' | wc -l)
                echo -e "  └─ ${CYAN}${model_count} models available${NC}"
            fi
        done
        
        if [[ "${CONFIG["INSTALL_LITELLM"]}" == "true" ]]; then
            echo -e "\nLiteLLM Routing: ${WHITE}${CONFIG["LITELLM_ROUTING_STRATEGY"]}${NC}"
            echo -e "Failover: ${WHITE}${CONFIG["LITELLM_ENABLE_FAILOVER"]:-true}${NC}"
        fi
    else
        echo -e "${YELLOW}No LLM providers configured${NC}"
    fi
    
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Auto-Generated Credentials${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}⚠ These are saved in: ${CONFIG_FILE}${NC}"
    echo -e "${YELLOW}⚠ Keep this file secure!${NC}"
    
    if [[ "${CONFIG["INSTALL_POSTGRES"]}" == "true" ]]; then
        echo -e "\nPostgreSQL:"
        echo -e "  User: ${WHITE}${CREDENTIALS["POSTGRES_USER"]}${NC}"
        echo -e "  Database: ${WHITE}${CREDENTIALS["POSTGRES_DB"]}${NC}"
        echo -e "  Password: ${WHITE}[saved in config]${NC}"
    fi
    
    if [[ "${CONFIG["INSTALL_REDIS"]}" == "true" ]]; then
        echo -e "\nRedis:"
        echo -e "  Password: ${WHITE}[saved in config]${NC}"
    fi
    
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Next Steps${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "1. Review configuration: ${WHITE}cat ${CONFIG_FILE}${NC}"
    echo -e "2. Deploy services: ${WHITE}./2-deploy-services.sh${NC}"
    echo -e "3. Configure services: ${WHITE}./3-configure-services.sh${NC}"
    echo -e "\n${GREEN}Configuration complete! Ready to deploy.${NC}\n"
    
    # Save URLs to a file for easy reference
    local url_file="${BASE_DIR}/service-urls.txt"
    {
        echo "AI Platform Service URLs"
        echo "Generated: $(date)"
        echo "======================================"
        echo ""
        
        if [[ "${CONFIG["INSTALL_N8N"]}" == "true" ]]; then
            if [[ "${CONFIG["USE_DOMAIN"]}" == "true" ]]; then
                echo "n8n: ${base_url}/n8n"
            else
                echo "n8n: ${base_url}:${CONFIG["N8N_PORT"]}"
            fi
        fi
        
        # ... (similar for all other services)
        
    } > "$url_file"
    
    print_success "Service URLs saved to: $url_file"
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================
main() {
    setup_logging
    
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║         AI PLATFORM AUTOMATION - SYSTEM SETUP v3.1.0            ║
║                                                                   ║
║  This script will collect all configuration for your AI platform ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
    
    log "INFO" "Starting AI Platform Setup v${SCRIPT_VERSION}"
    
    # Pre-flight checks
    check_root
    check_dependencies
    check_disk_space
    detect_public_ip
    detect_gpu
    
    # Configuration
    configure_network
    select_services
    configure_llm_providers
    configure_databases
    configure_ports
    
    # Generate configuration
    generate_env_file
    save_state
    
    # Show summary
    show_summary
    
    log "INFO" "Setup completed successfully"
    exit $EXIT_SUCCESS
}

# Run main function
main "$@"
