#!/bin/bash
################################################################################
# AI Platform Automation - System Setup Script
# Version: 1.1.0-COMPLETE-RESTORE
# Part 1 of 4: Setup & Core Functions
################################################################################

set -euo pipefail

################################################################################
# Color Definitions
################################################################################
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

################################################################################
# Global Configuration
################################################################################
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly CONFIG_DIR="$PROJECT_ROOT/config"
readonly DATA_DIR="/mnt/data"
readonly ENV_FILE="$CONFIG_DIR/.env"
readonly LOG_FILE="$PROJECT_ROOT/setup.log"

# Version tracking
readonly SCRIPT_VERSION="1.1.0-COMPLETE"
readonly LAST_WORKING_BASE="7df4b977"

# Service tracking
declare -A SERVICE_URLS
declare -A SERVICE_PORTS
declare -A SERVICE_HEALTH_ENDPOINTS

# Feature flags
INSTALL_CORE_SERVICES=false
INSTALL_AI_SERVICES=false
INSTALL_MONITORING=false
INSTALL_N8N=false
INSTALL_OLLAMA=false
INSTALL_OPENWEBUI=false
INSTALL_LITELLM=false
INSTALL_FLOWISE=false
INSTALL_DIFY=false
INSTALL_ANYTHINGLLM=false
INSTALL_OPENCLAW=false
INSTALL_GRAFANA=false
INSTALL_PROMETHEUS=false
INSTALL_LOKI=false

################################################################################
# Logging Setup
################################################################################
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOG_FILE" >&2
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $*" | tee -a "$LOG_FILE"
}

################################################################################
# UI/UX Functions
################################################################################

print_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
╔════════════════════════════════════════════════════════════════════╗
║                                                                    ║
║       🚀 AI PLATFORM AUTOMATION - COMPLETE SETUP v1.1.0           ║
║                                                                    ║
║       • Full Feature Restoration from Working Base                 ║
║       • Enhanced Service Selection with Categories                 ║
║       • Dynamic Model Discovery & Selection                        ║
║       • Multi-Method Authentication Support                        ║
║       • Vector Database Integration                                ║
║       • Port Health Checks & Monitoring                            ║
║                                                                    ║
╚════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo ""
}

print_header() {
    local title="$1"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}  $title${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
    log_success "$1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
    log_error "$1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
    log_info "$1"
}

print_step() {
    echo -e "${MAGENTA}▶${NC} $1"
}

prompt_continue() {
    echo ""
    read -p "Press Enter to continue..."
    echo ""
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local response
    
    while true; do
        if [[ "$default" == "y" ]]; then
            read -p "$prompt [Y/n]: " response
            response=${response:-y}
        else
            read -p "$prompt [y/N]: " response
            response=${response:-n}
        fi
        
        case "$response" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

################################################################################
# System Checks
################################################################################

check_root() {
    print_step "Checking root privileges..."
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
    print_success "Running as root"
}

check_os() {
    print_step "Checking operating system..."
    
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
    
    source /etc/os-release
    
    case "$ID" in
        ubuntu|debian)
            print_success "Detected: $PRETTY_NAME"
            ;;
        centos|rhel|fedora)
            print_success "Detected: $PRETTY_NAME"
            ;;
        *)
            print_warning "Unsupported OS: $PRETTY_NAME"
            if ! prompt_yes_no "Continue anyway?"; then
                exit 1
            fi
            ;;
    esac
}

check_disk_space() {
    print_step "Checking disk space..."
    
    local required_gb=50
    local available_gb=$(df -BG "$PROJECT_ROOT" | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [[ $available_gb -lt $required_gb ]]; then
        print_warning "Low disk space: ${available_gb}GB available, ${required_gb}GB recommended"
        if ! prompt_yes_no "Continue anyway?"; then
            exit 1
        fi
    else
        print_success "Sufficient disk space: ${available_gb}GB available"
    fi
}

check_memory() {
    print_step "Checking system memory..."
    
    local total_mem=$(free -g | awk '/^Mem:/{print $2}')
    local required_mem=8
    
    if [[ $total_mem -lt $required_mem ]]; then
        print_warning "Low memory: ${total_mem}GB total, ${required_mem}GB recommended"
        if ! prompt_yes_no "Continue anyway?"; then
            exit 1
        fi
    else
        print_success "Sufficient memory: ${total_mem}GB total"
    fi
}

check_prerequisites() {
    print_header "CHECKING PREREQUISITES"
    
    check_disk_space
    check_memory
    
    print_step "Checking required commands..."
    
    local missing_commands=()
    local commands=("curl" "git" "jq")
    
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        print_warning "Missing commands: ${missing_commands[*]}"
        print_info "Installing missing prerequisites..."
        
        if command -v apt-get &> /dev/null; then
            apt-get update
            apt-get install -y curl git jq
        elif command -v yum &> /dev/null; then
            yum install -y curl git jq
        fi
    fi
    
    print_success "All prerequisites checked"
}

################################################################################
# Docker Installation
################################################################################

install_docker() {
    print_header "DOCKER INSTALLATION"
    
    if command -v docker &> /dev/null && command -v docker-compose &> /dev/null; then
        print_success "Docker already installed: $(docker --version)"
        print_success "Docker Compose already installed: $(docker-compose --version)"
        return 0
    fi
    
    print_step "Installing Docker..."
    
    # Install Docker
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    
    # Install Docker Compose
    local compose_version="2.24.0"
    curl -L "https://github.com/docker/compose/releases/download/v${compose_version}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Start Docker
    systemctl enable docker
    systemctl start docker
    
    print_success "Docker installed successfully"
    print_success "Docker Compose installed successfully"
}

generate_password() {
    local length=${1:-32}
    LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c "$length"
}
################################################################################
# PART 2 OF 4: Network, Service Selection & Configuration
################################################################################

################################################################################
# Network Configuration
################################################################################

configure_network() {
    print_header "NETWORK CONFIGURATION"
    
    print_step "Detecting network configuration..."
    
    # Get primary network interface
    local primary_interface=$(ip route | grep default | awk '{print $5}' | head -n1)
    print_info "Primary interface: $primary_interface"
    
    # Get IP address
    local ip_address=$(ip addr show "$primary_interface" | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
    print_info "IP Address: $ip_address"
    
    # Detect if we're using Tailscale
    local tailscale_ip=""
    if command -v tailscale &> /dev/null; then
        tailscale_ip=$(tailscale ip -4 2>/dev/null || echo "")
        if [[ -n "$tailscale_ip" ]]; then
            print_success "Tailscale detected: $tailscale_ip"
        fi
    fi
    
    echo ""
    echo -e "${WHITE}Available network options:${NC}"
    echo "1) Use local IP: $ip_address"
    [[ -n "$tailscale_ip" ]] && echo "2) Use Tailscale IP: $tailscale_ip"
    echo "3) Use localhost (127.0.0.1)"
    echo "4) Enter custom IP/hostname"
    echo ""
    
    local choice
    read -p "Select network option [1]: " choice
    choice=${choice:-1}
    
    case $choice in
        1)
            BASE_URL="http://$ip_address"
            ;;
        2)
            if [[ -n "$tailscale_ip" ]]; then
                BASE_URL="http://$tailscale_ip"
            else
                print_error "Tailscale not available"
                BASE_URL="http://$ip_address"
            fi
            ;;
        3)
            BASE_URL="http://127.0.0.1"
            ;;
        4)
            read -p "Enter custom IP or hostname: " custom_host
            BASE_URL="http://$custom_host"
            ;;
        *)
            print_warning "Invalid choice, using local IP"
            BASE_URL="http://$ip_address"
            ;;
    esac
    
    print_success "Base URL configured: $BASE_URL"
    
    # Store in environment
    echo "BASE_URL=$BASE_URL" >> "$ENV_FILE"
}

################################################################################
# Port Health Checks
################################################################################

check_port_available() {
    local port=$1
    local service_name=$2
    
    if ss -tuln | grep -q ":$port "; then
        print_warning "Port $port is already in use (needed for $service_name)"
        if prompt_yes_no "Attempt to identify the conflicting service?"; then
            local pid=$(lsof -ti:$port 2>/dev/null || echo "")
            if [[ -n "$pid" ]]; then
                local process=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
                print_info "Port $port is used by: $process (PID: $pid)"
                if prompt_yes_no "Stop this service?"; then
                    kill "$pid" 2>/dev/null && print_success "Service stopped" || print_error "Failed to stop service"
                fi
            fi
        fi
        return 1
    fi
    return 0
}

check_service_ports() {
    print_header "PORT AVAILABILITY CHECK"
    
    local conflicts=0
    
    # Check core service ports
    [[ "$INSTALL_N8N" == "true" ]] && ! check_port_available 5678 "N8N" && ((conflicts++))
    [[ "$INSTALL_OLLAMA" == "true" ]] && ! check_port_available 11434 "Ollama" && ((conflicts++))
    [[ "$INSTALL_OPENWEBUI" == "true" ]] && ! check_port_available 3000 "OpenWebUI" && ((conflicts++))
    [[ "$INSTALL_LITELLM" == "true" ]] && ! check_port_available 4000 "LiteLLM" && ((conflicts++))
    [[ "$INSTALL_FLOWISE" == "true" ]] && ! check_port_available 3001 "Flowise" && ((conflicts++))
    [[ "$INSTALL_DIFY" == "true" ]] && ! check_port_available 3002 "Dify" && ((conflicts++))
    [[ "$INSTALL_ANYTHINGLLM" == "true" ]] && ! check_port_available 3003 "AnythingLLM" && ((conflicts++))
    [[ "$INSTALL_OPENCLAW" == "true" ]] && ! check_port_available 8080 "OpenClaw" && ((conflicts++))
    [[ "$INSTALL_GRAFANA" == "true" ]] && ! check_port_available 3100 "Grafana" && ((conflicts++))
    [[ "$INSTALL_PROMETHEUS" == "true" ]] && ! check_port_available 9090 "Prometheus" && ((conflicts++))
    
    if [[ $conflicts -gt 0 ]]; then
        print_warning "Found $conflicts port conflict(s)"
        if ! prompt_yes_no "Continue anyway? (Services may fail to start)"; then
            exit 1
        fi
    else
        print_success "All required ports are available"
    fi
}

################################################################################
# Service Selection with Categories
################################################################################

select_services() {
    print_header "SERVICE SELECTION"
    
    echo -e "${WHITE}Select services to install:${NC}"
    echo ""
    
    # Category 1: Core Services
    echo -e "${CYAN}━━━ CORE SERVICES ━━━${NC}"
    if prompt_yes_no "Install Core Services (N8N, PostgreSQL, Redis)?"; then
        INSTALL_CORE_SERVICES=true
        INSTALL_N8N=true
    fi
    echo ""
    
    # Category 2: AI Platform Selection
    echo -e "${CYAN}━━━ AI PLATFORMS (Choose one or more) ━━━${NC}"
    echo ""
    echo -e "${WHITE}1. Flowise${NC} - Visual low-code LLM builder"
    echo -e "${WHITE}2. Dify${NC} - Complete AI app development platform"
    echo -e "${WHITE}3. AnythingLLM${NC} - Document chat and RAG platform"
    echo ""
    
    read -p "Select platforms (e.g., 1,2 or 1-3 or 'all') [none]: " platform_choice
    
    case "$platform_choice" in
        *1*|*all*) INSTALL_FLOWISE=true; INSTALL_AI_SERVICES=true ;;
    esac
    case "$platform_choice" in
        *2*|*all*) INSTALL_DIFY=true; INSTALL_AI_SERVICES=true ;;
    esac
    case "$platform_choice" in
        *3*|*all*) INSTALL_ANYTHINGLLM=true; INSTALL_AI_SERVICES=true ;;
    esac
    
    echo ""
    
    # Category 3: LLM Infrastructure
    echo -e "${CYAN}━━━ LLM INFRASTRUCTURE ━━━${NC}"
    if prompt_yes_no "Install Ollama (Local LLM runtime)?"; then
        INSTALL_OLLAMA=true
        INSTALL_AI_SERVICES=true
    fi
    
    if prompt_yes_no "Install OpenWebUI (Chat interface for Ollama)?"; then
        INSTALL_OPENWEBUI=true
        INSTALL_AI_SERVICES=true
        if [[ "$INSTALL_OLLAMA" != "true" ]]; then
            print_warning "OpenWebUI works best with Ollama"
        fi
    fi
    
    if prompt_yes_no "Install LiteLLM (Multi-provider LLM router)?"; then
        INSTALL_LITELLM=true
        INSTALL_AI_SERVICES=true
    fi
    echo ""
    
    # Category 4: AI Agents
    echo -e "${CYAN}━━━ AI AGENTS & AUTOMATION ━━━${NC}"
    if prompt_yes_no "Install OpenClaw (AI agent platform)?"; then
        INSTALL_OPENCLAW=true
        INSTALL_AI_SERVICES=true
    fi
    echo ""
    
    # Category 5: Monitoring
    echo -e "${CYAN}━━━ MONITORING & OBSERVABILITY ━━━${NC}"
    if prompt_yes_no "Install Monitoring Stack (Grafana, Prometheus, Loki)?"; then
        INSTALL_MONITORING=true
        INSTALL_GRAFANA=true
        INSTALL_PROMETHEUS=true
        INSTALL_LOKI=true
    fi
    
    # Display summary
    echo ""
    print_header "SELECTED SERVICES SUMMARY"
    
    if [[ "$INSTALL_CORE_SERVICES" == "true" ]]; then
        echo -e "${GREEN}✓${NC} Core Services: N8N, PostgreSQL, Redis"
    fi
    
    if [[ "$INSTALL_AI_SERVICES" == "true" ]]; then
        echo -e "${GREEN}✓${NC} AI Services:"
        [[ "$INSTALL_OLLAMA" == "true" ]] && echo "  • Ollama"
        [[ "$INSTALL_OPENWEBUI" == "true" ]] && echo "  • OpenWebUI"
        [[ "$INSTALL_LITELLM" == "true" ]] && echo "  • LiteLLM"
        [[ "$INSTALL_FLOWISE" == "true" ]] && echo "  • Flowise"
        [[ "$INSTALL_DIFY" == "true" ]] && echo "  • Dify"
        [[ "$INSTALL_ANYTHINGLLM" == "true" ]] && echo "  • AnythingLLM"
        [[ "$INSTALL_OPENCLAW" == "true" ]] && echo "  • OpenClaw"
    fi
    
    if [[ "$INSTALL_MONITORING" == "true" ]]; then
        echo -e "${GREEN}✓${NC} Monitoring: Grafana, Prometheus, Loki"
    fi
    
    echo ""
    if ! prompt_yes_no "Proceed with these services?"; then
        print_info "Restarting service selection..."
        select_services
        return
    fi
}

################################################################################
# Ollama Model Configuration
################################################################################

configure_ollama_models() {
    if [[ "$INSTALL_OLLAMA" != "true" ]]; then
        return 0
    fi
    
    print_header "OLLAMA MODEL CONFIGURATION"
    
    print_step "Fetching available models from Ollama library..."
    
    # Popular models with descriptions
    declare -A MODELS=(
        [1]="llama2:latest|Llama 2 - Meta's open-source LLM (7B)|3.8GB"
        [2]="mistral:latest|Mistral 7B - High performance model|4.1GB"
        [3]="codellama:latest|Code Llama - Specialized for coding|3.8GB"
        [4]="neural-chat:latest|Neural Chat - Optimized for conversations|4.1GB"
        [5]="orca-mini:latest|Orca Mini - Compact but capable|1.9GB"
        [6]="vicuna:latest|Vicuna - Strong instruction following|3.8GB"
        [7]="llama2:13b|Llama 2 13B - Larger, more capable|7.4GB"
        [8]="mixtral:latest|Mixtral 8x7B - Mixture of experts|26GB"
    )
    
    echo -e "${WHITE}Available Models:${NC}"
    echo ""
    
    for key in $(echo "${!MODELS[@]}" | tr ' ' '\n' | sort -n); do
        IFS='|' read -r model_name description size <<< "${MODELS[$key]}"
        printf "%2d) ${CYAN}%-20s${NC} - %s ${YELLOW}[%s]${NC}\n" "$key" "$model_name" "$description" "$size"
    done
    
    echo ""
    echo "9) Enter custom model"
    echo "0) Skip model installation"
    echo ""
    
    read -p "Select models to install (e.g., 1,2,4 or 1-3) [1]: " model_selection
    model_selection=${model_selection:-1}
    
    # Parse selection
    local selected_models=()
    
    if [[ "$model_selection" == "0" ]]; then
        print_info "Skipping model installation"
        return 0
    elif [[ "$model_selection" == "9" ]]; then
        read -p "Enter custom model name: " custom_model
        selected_models+=("$custom_model")
    else
        # Handle ranges and comma-separated values
        IFS=',' read -ra SELECTIONS <<< "$model_selection"
        for sel in "${SELECTIONS[@]}"; do
            if [[ "$sel" =~ ([0-9]+)-([0-9]+) ]]; then
                # Range
                for ((i=${BASH_REMATCH[1]}; i<=${BASH_REMATCH[2]}; i++)); do
                    if [[ -n "${MODELS[$i]}" ]]; then
                        IFS='|' read -r model_name _ _ <<< "${MODELS[$i]}"
                        selected_models+=("$model_name")
                    fi
                done
            else
                # Single number
                if [[ -n "${MODELS[$sel]}" ]]; then
                    IFS='|' read -r model_name _ _ <<< "${MODELS[$sel]}"
                    selected_models+=("$model_name")
                fi
            fi
        done
    fi
    
    if [[ ${#selected_models[@]} -eq 0 ]]; then
        print_warning "No valid models selected"
        return 0
    fi
    
    echo ""
    print_info "Selected models: ${selected_models[*]}"
    echo ""
    
    if prompt_yes_no "Download these models now? (Requires Ollama to be running)"; then
        OLLAMA_MODELS="${selected_models[*]}"
        echo "OLLAMA_MODELS=\"${OLLAMA_MODELS}\"" >> "$ENV_FILE"
        print_success "Models will be downloaded after Ollama starts"
    else
        print_info "Models can be downloaded later using: ollama pull <model-name>"
    fi
}

################################################################################
# LLM Provider Configuration
################################################################################

configure_llm_providers() {
    print_header "LLM PROVIDER CONFIGURATION"
    
    echo -e "${WHITE}Configure API keys for external LLM providers:${NC}"
    echo ""
    
    # OpenAI
    if prompt_yes_no "Configure OpenAI API?"; then
        read -p "Enter OpenAI API Key: " openai_key
        echo "OPENAI_API_KEY=$openai_key" >> "$ENV_FILE"
        print_success "OpenAI configured"
    fi
    echo ""
    
    # Anthropic Claude
    if prompt_yes_no "Configure Anthropic (Claude) API?"; then
        read -p "Enter Anthropic API Key: " anthropic_key
        echo "ANTHROPIC_API_KEY=$anthropic_key" >> "$ENV_FILE"
        print_success "Anthropic configured"
    fi
    echo ""
    
    # Google AI
    if prompt_yes_no "Configure Google AI (Gemini) API?"; then
        read -p "Enter Google AI API Key: " google_key
        echo "GOOGLE_AI_API_KEY=$google_key" >> "$ENV_FILE"
        print_success "Google AI configured"
    fi
    echo ""
    
    print_info "Provider keys stored securely in .env"
}
################################################################################
# PART 3 OF 4: Environment & Docker Compose Generation
################################################################################

################################################################################
# Environment File Generation
################################################################################

generate_env_file() {
    print_header "GENERATING ENVIRONMENT CONFIGURATION"
    
    mkdir -p "$CONFIG_DIR"
    
    # Start fresh or append
    if [[ ! -f "$ENV_FILE" ]]; then
        cat > "$ENV_FILE" << EOF
# AI Platform Environment Configuration
# Generated: $(date)
# Version: $SCRIPT_VERSION

# Network Configuration
BASE_URL=$BASE_URL

# Security
POSTGRES_PASSWORD=$(generate_password)
REDIS_PASSWORD=$(generate_password)
N8N_ENCRYPTION_KEY=$(generate_password 32)

EOF
    fi
    
    # Generate passwords for each service
    if [[ "$INSTALL_N8N" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF
# N8N Configuration
N8N_PORT=5678
N8N_PROTOCOL=http
N8N_HOST=${BASE_URL#http://}
WEBHOOK_URL=${BASE_URL}:5678/
N8N_ENCRYPTION_KEY=$(grep N8N_ENCRYPTION_KEY "$ENV_FILE" | cut -d'=' -f2)

EOF
    fi
    
    if [[ "$INSTALL_OLLAMA" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF
# Ollama Configuration
OLLAMA_PORT=11434
OLLAMA_HOST=0.0.0.0
OLLAMA_ORIGINS=*

EOF
    fi
    
    if [[ "$INSTALL_OPENWEBUI" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF
# OpenWebUI Configuration
OPENWEBUI_PORT=3000
OLLAMA_BASE_URL=http://ollama:11434

EOF
    fi
    
    if [[ "$INSTALL_LITELLM" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF
# LiteLLM Configuration
LITELLM_PORT=4000
LITELLM_MASTER_KEY=$(generate_password 24)

EOF
    fi
    
    if [[ "$INSTALL_FLOWISE" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF
# Flowise Configuration
FLOWISE_PORT=3001
FLOWISE_USERNAME=admin
FLOWISE_PASSWORD=$(generate_password 16)

EOF
    fi
    
    if [[ "$INSTALL_DIFY" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF
# Dify Configuration
DIFY_PORT=3002
DIFY_API_PORT=5001
SECRET_KEY=$(generate_password 32)

EOF
    fi
    
    if [[ "$INSTALL_ANYTHINGLLM" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF
# AnythingLLM Configuration
ANYTHINGLLM_PORT=3003
STORAGE_DIR=${DATA_DIR}/anythingllm

EOF
    fi
    
    if [[ "$INSTALL_OPENCLAW" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF
# OpenClaw Configuration
OPENCLAW_PORT=8080
OPENCLAW_API_KEY=$(generate_password 32)

EOF
    fi
    
    if [[ "$INSTALL_GRAFANA" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF
# Grafana Configuration
GRAFANA_PORT=3100
GF_SECURITY_ADMIN_PASSWORD=$(generate_password 16)
GF_SECURITY_ADMIN_USER=admin

EOF
    fi
    
    if [[ "$INSTALL_PROMETHEUS" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF
# Prometheus Configuration
PROMETHEUS_PORT=9090

EOF
    fi
    
    if [[ "$INSTALL_LOKI" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF
# Loki Configuration
LOKI_PORT=3100

EOF
    fi
    
    # Database configuration (if any service needs it)
    if [[ "$INSTALL_CORE_SERVICES" == "true" ]] || [[ "$INSTALL_AI_SERVICES" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF
# Database Configuration
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=platform_db
POSTGRES_USER=platform_user
POSTGRES_PASSWORD=$(grep POSTGRES_PASSWORD "$ENV_FILE" | cut -d'=' -f2)

# Redis Configuration
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=$(grep REDIS_PASSWORD "$ENV_FILE" | cut -d'=' -f2)

EOF
    fi
    
    # Set secure permissions
    chmod 600 "$ENV_FILE"
    
    print_success "Environment file generated: $ENV_FILE"
}

################################################################################
# Docker Compose File Generation
################################################################################

generate_docker_compose() {
    print_header "GENERATING DOCKER COMPOSE CONFIGURATION"
    
    local compose_file="$PROJECT_ROOT/docker-compose.yml"
    
    cat > "$compose_file" << 'EOF'
version: '3.8'

networks:
  ai_platform:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/16

volumes:
  postgres_data:
  redis_data:
  n8n_data:
  ollama_data:
  grafana_data:
  prometheus_data:
  loki_data:

services:
EOF
    
    # Add PostgreSQL if needed
    if [[ "$INSTALL_CORE_SERVICES" == "true" ]] || [[ "$INSTALL_DIFY" == "true" ]] || [[ "$INSTALL_FLOWISE" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'

  postgres:
    image: postgres:15-alpine
    container_name: platform_postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - ai_platform
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5
EOF
    fi
    
    # Add Redis if needed
    if [[ "$INSTALL_CORE_SERVICES" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'

  redis:
    image: redis:7-alpine
    container_name: platform_redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - redis_data:/data
    networks:
      - ai_platform
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
EOF
    fi
    
    # Add N8N
    if [[ "$INSTALL_N8N" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'

  n8n:
    image: n8nio/n8n:latest
    container_name: platform_n8n
    restart: unless-stopped
    ports:
      - "${N8N_PORT}:5678"
    environment:
      - N8N_PROTOCOL=${N8N_PROTOCOL}
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=${N8N_PORT}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - WEBHOOK_URL=${WEBHOOK_URL}
      - GENERIC_TIMEZONE=America/New_York
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - ai_platform
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
EOF
    fi
    
    # Add Ollama
    if [[ "$INSTALL_OLLAMA" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'

  ollama:
    image: ollama/ollama:latest
    container_name: platform_ollama
    restart: unless-stopped
    ports:
      - "${OLLAMA_PORT}:11434"
    environment:
      - OLLAMA_HOST=${OLLAMA_HOST}
      - OLLAMA_ORIGINS=${OLLAMA_ORIGINS}
    volumes:
      - ollama_data:/root/.ollama
    networks:
      - ai_platform
EOF
        
        # Add GPU support if available
        if command -v nvidia-smi &> /dev/null; then
            cat >> "$compose_file" << 'EOF'
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
EOF
        fi
    fi
    
    # Add OpenWebUI
    if [[ "$INSTALL_OPENWEBUI" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'

  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: platform_openwebui
    restart: unless-stopped
    ports:
      - "${OPENWEBUI_PORT}:8080"
    environment:
      - OLLAMA_BASE_URL=${OLLAMA_BASE_URL}
      - WEBUI_SECRET_KEY=$(openssl rand -hex 32)
    volumes:
      - ${DATA_DIR}/openwebui:/app/backend/data
    networks:
      - ai_platform
EOF
        
        if [[ "$INSTALL_OLLAMA" == "true" ]]; then
            cat >> "$compose_file" << 'EOF'
    depends_on:
      - ollama
EOF
        fi
    fi
    
    # Add LiteLLM
    if [[ "$INSTALL_LITELLM" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'

  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: platform_litellm
    restart: unless-stopped
    ports:
      - "${LITELLM_PORT}:4000"
    environment:
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
      - LITELLM_SALT_KEY=$(openssl rand -hex 16)
      - DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
    volumes:
      - ${CONFIG_DIR}/litellm_config.yaml:/app/config.yaml
    networks:
      - ai_platform
    command: --config /app/config.yaml --port 4000
EOF
    fi
    
    # Add Flowise
    if [[ "$INSTALL_FLOWISE" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'

  flowise:
    image: flowiseai/flowise:latest
    container_name: platform_flowise
    restart: unless-stopped
    ports:
      - "${FLOWISE_PORT}:3000"
    environment:
      - PORT=3000
      - FLOWISE_USERNAME=${FLOWISE_USERNAME}
      - FLOWISE_PASSWORD=${FLOWISE_PASSWORD}
      - DATABASE_TYPE=postgres
      - DATABASE_HOST=postgres
      - DATABASE_PORT=5432
      - DATABASE_USER=${POSTGRES_USER}
      - DATABASE_PASSWORD=${POSTGRES_PASSWORD}
      - DATABASE_NAME=${POSTGRES_DB}
    volumes:
      - ${DATA_DIR}/flowise:/root/.flowise
    networks:
      - ai_platform
    depends_on:
      postgres:
        condition: service_healthy
EOF
    fi
    
    # Add Dify
    if [[ "$INSTALL_DIFY" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'

  dify:
    image: langgenius/dify-api:latest
    container_name: platform_dify
    restart: unless-stopped
    ports:
      - "${DIFY_PORT}:5001"
    environment:
      - SECRET_KEY=${SECRET_KEY}
      - DB_USERNAME=${POSTGRES_USER}
      - DB_PASSWORD=${POSTGRES_PASSWORD}
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_DATABASE=${POSTGRES_DB}
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=${REDIS_PASSWORD}
    volumes:
      - ${DATA_DIR}/dify:/app/api/storage
    networks:
      - ai_platform
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
EOF
    fi
    
    # Add AnythingLLM
    if [[ "$INSTALL_ANYTHINGLLM" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'

  anythingllm:
    image: mintplexlabs/anythingllm:latest
    container_name: platform_anythingllm
    restart: unless-stopped
    ports:
      - "${ANYTHINGLLM_PORT}:3001"
    environment:
      - STORAGE_DIR=/app/server/storage
    volumes:
      - ${STORAGE_DIR}:/app/server/storage
    networks:
      - ai_platform
EOF
    fi
    
    # Add OpenClaw
    if [[ "$INSTALL_OPENCLAW" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'

  openclaw:
    image: openclaw/openclaw:latest
    container_name: platform_openclaw
    restart: unless-stopped
    ports:
      - "${OPENCLAW_PORT}:8080"
    environment:
      - API_KEY=${OPENCLAW_API_KEY}
    volumes:
      - ${DATA_DIR}/openclaw:/data
    networks:
      - ai_platform
EOF
    fi
    
    # Add Grafana
    if [[ "$INSTALL_GRAFANA" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'

  grafana:
    image: grafana/grafana:latest
    container_name: platform_grafana
    restart: unless-stopped
    ports:
      - "${GRAFANA_PORT}:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=${GF_SECURITY_ADMIN_USER}
      - GF_SECURITY_ADMIN_PASSWORD=${GF_SECURITY_ADMIN_PASSWORD}
      - GF_INSTALL_PLUGINS=redis-datasource
    volumes:
      - grafana_data:/var/lib/grafana
      - ${CONFIG_DIR}/grafana/provisioning:/etc/grafana/provisioning
    networks:
      - ai_platform
EOF
    fi
    
    # Add Prometheus
    if [[ "$INSTALL_PROMETHEUS" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'

  prometheus:
    image: prom/prometheus:latest
    container_name: platform_prometheus
    restart: unless-stopped
    ports:
      - "${PROMETHEUS_PORT}:9090"
    volumes:
      - prometheus_data:/prometheus
      - ${CONFIG_DIR}/prometheus.yml:/etc/prometheus/prometheus.yml
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    networks:
      - ai_platform
EOF
    fi
    
    # Add Loki
    if [[ "$INSTALL_LOKI" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'

  loki:
    image: grafana/loki:latest
    container_name: platform_loki
    restart: unless-stopped
    ports:
      - "${LOKI_PORT}:3100"
    volumes:
      - loki_data:/loki
      - ${CONFIG_DIR}/loki-config.yaml:/etc/loki/local-config.yaml
    command: -config.file=/etc/loki/local-config.yaml
    networks:
      - ai_platform
EOF
    fi
    
    print_success "Docker Compose file generated: $compose_file"
}
################################################################################
# PART 4 OF 4: Service Deployment, Health Checks & Main Function
################################################################################

################################################################################
# Service Health Checks
################################################################################

wait_for_service() {
    local service_name=$1
    local health_url=$2
    local max_attempts=${3:-30}
    local attempt=1

    print_step "Waiting for $service_name to be healthy..."

    while [[ $attempt -le $max_attempts ]]; do
        if curl -sf "$health_url" > /dev/null 2>&1; then
            print_success "$service_name is healthy"
            return 0
        fi

        echo -ne "\r${YELLOW}Attempt $attempt/$max_attempts...${NC}"
        sleep 2
        ((attempt++))
    done

    echo ""
    print_error "$service_name failed to become healthy"
    return 1
}

check_service_health() {
    print_header "SERVICE HEALTH CHECK"

    local all_healthy=true

    if [[ "$INSTALL_N8N" == "true" ]]; then
        if wait_for_service "N8N" "${BASE_URL}:${N8N_PORT}/healthz"; then
            SERVICE_URLS["n8n"]="${BASE_URL}:${N8N_PORT}"
        else
            all_healthy=false
        fi
    fi

    if [[ "$INSTALL_OLLAMA" == "true" ]]; then
        if wait_for_service "Ollama" "${BASE_URL}:${OLLAMA_PORT}"; then
            SERVICE_URLS["ollama"]="${BASE_URL}:${OLLAMA_PORT}"
        else
            all_healthy=false
        fi
    fi

    if [[ "$INSTALL_OPENWEBUI" == "true" ]]; then
        if wait_for_service "OpenWebUI" "${BASE_URL}:${OPENWEBUI_PORT}"; then
            SERVICE_URLS["openwebui"]="${BASE_URL}:${OPENWEBUI_PORT}"
        else
            all_healthy=false
        fi
    fi

    if [[ "$INSTALL_LITELLM" == "true" ]]; then
        if wait_for_service "LiteLLM" "${BASE_URL}:${LITELLM_PORT}/health"; then
            SERVICE_URLS["litellm"]="${BASE_URL}:${LITELLM_PORT}"
        else
            all_healthy=false
        fi
    fi

    if [[ "$INSTALL_FLOWISE" == "true" ]]; then
        if wait_for_service "Flowise" "${BASE_URL}:${FLOWISE_PORT}"; then
            SERVICE_URLS["flowise"]="${BASE_URL}:${FLOWISE_PORT}"
        else
            all_healthy=false
        fi
    fi

    if [[ "$INSTALL_DIFY" == "true" ]]; then
        if wait_for_service "Dify" "${BASE_URL}:${DIFY_PORT}"; then
            SERVICE_URLS["dify"]="${BASE_URL}:${DIFY_PORT}"
        else
            all_healthy=false
        fi
    fi

    if [[ "$INSTALL_ANYTHINGLLM" == "true" ]]; then
        if wait_for_service "AnythingLLM" "${BASE_URL}:${ANYTHINGLLM_PORT}"; then
            SERVICE_URLS["anythingllm"]="${BASE_URL}:${ANYTHINGLLM_PORT}"
        else
            all_healthy=false
        fi
    fi

    if [[ "$INSTALL_GRAFANA" == "true" ]]; then
        if wait_for_service "Grafana" "${BASE_URL}:${GRAFANA_PORT}/api/health"; then
            SERVICE_URLS["grafana"]="${BASE_URL}:${GRAFANA_PORT}"
        else
            all_healthy=false
        fi
    fi

    if [[ "$INSTALL_PROMETHEUS" == "true" ]]; then
        if wait_for_service "Prometheus" "${BASE_URL}:${PROMETHEUS_PORT}/-/healthy"; then
            SERVICE_URLS["prometheus"]="${BASE_URL}:${PROMETHEUS_PORT}"
        else
            all_healthy=false
        fi
    fi

    if [[ "$all_healthy" == "true" ]]; then
        print_success "All services are healthy!"
    else
        print_warning "Some services may not be fully operational"
    fi
}

################################################################################
# Ollama Model Downloads
################################################################################

download_ollama_models() {
    if [[ -z "$OLLAMA_MODELS" ]]; then
        return 0
    fi

    print_header "DOWNLOADING OLLAMA MODELS"

    # Wait for Ollama to be ready
    print_step "Waiting for Ollama service..."
    sleep 5

    for model in $OLLAMA_MODELS; do
        print_step "Pulling model: $model"
        if docker exec platform_ollama ollama pull "$model"; then
            print_success "Successfully pulled: $model"
        else
            print_error "Failed to pull: $model"
        fi
    done
}

################################################################################
# Configuration File Generation
################################################################################

generate_config_files() {
    print_header "GENERATING CONFIGURATION FILES"

    # LiteLLM config
    if [[ "$INSTALL_LITELLM" == "true" ]]; then
        mkdir -p "$CONFIG_DIR"
        cat > "$CONFIG_DIR/litellm_config.yaml" << EOF
model_list:
  - model_name: gpt-3.5-turbo
    litellm_params:
      model: gpt-3.5-turbo
      api_key: \${OPENAI_API_KEY}

  - model_name: claude-3-sonnet
    litellm_params:
      model: claude-3-sonnet-20240229
      api_key: \${ANTHROPIC_API_KEY}

  - model_name: gemini-pro
    litellm_params:
      model: gemini-pro
      api_key: \${GOOGLE_AI_API_KEY}

litellm_settings:
  drop_params: true
  set_verbose: false
EOF
        print_success "LiteLLM config generated"
    fi

    # Prometheus config
    if [[ "$INSTALL_PROMETHEUS" == "true" ]]; then
        cat > "$CONFIG_DIR/prometheus.yml" << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'docker'
    static_configs:
      - targets: ['host.docker.internal:9323']
EOF

        if [[ "$INSTALL_N8N" == "true" ]]; then
            cat >> "$CONFIG_DIR/prometheus.yml" << EOF

  - job_name: 'n8n'
    static_configs:
      - targets: ['n8n:5678']
EOF
        fi

        print_success "Prometheus config generated"
    fi

    # Loki config
    if [[ "$INSTALL_LOKI" == "true" ]]; then
        cat > "$CONFIG_DIR/loki-config.yaml" << EOF
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
  chunk_idle_period: 5m
  chunk_retain_period: 30s

schema_config:
  configs:
    - from: 2024-01-01
      store: boltdb
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb:
    directory: /loki/index
  filesystem:
    directory: /loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h
EOF
        print_success "Loki config generated"
    fi
}

################################################################################
# Post-Installation Summary
################################################################################

display_summary() {
    print_header "INSTALLATION COMPLETE!"

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           AI Platform Successfully Deployed!                   ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ ${#SERVICE_URLS[@]} -gt 0 ]]; then
        echo -e "${WHITE}📍 Service URLs:${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

        for service in "${!SERVICE_URLS[@]}"; do
            local url="${SERVICE_URLS[$service]}"
            echo -e "  ${WHITE}${service}:${NC} ${BLUE}${url}${NC}"
        done
        echo ""
    fi

    # Display credentials
    echo -e "${WHITE}🔑 Credentials:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [[ "$INSTALL_FLOWISE" == "true" ]]; then
        local flowise_user=$(grep FLOWISE_USERNAME "$ENV_FILE" | cut -d'=' -f2)
        local flowise_pass=$(grep FLOWISE_PASSWORD "$ENV_FILE" | cut -d'=' -f2)
        echo -e "  ${WHITE}Flowise:${NC}"
        echo -e "    Username: ${GREEN}${flowise_user}${NC}"
        echo -e "    Password: ${GREEN}${flowise_pass}${NC}"
        echo ""
    fi

    if [[ "$INSTALL_GRAFANA" == "true" ]]; then
        local grafana_user=$(grep GF_SECURITY_ADMIN_USER "$ENV_FILE" | cut -d'=' -f2)
        local grafana_pass=$(grep GF_SECURITY_ADMIN_PASSWORD "$ENV_FILE" | cut -d'=' -f2)
        echo -e "  ${WHITE}Grafana:${NC}"
        echo -e "    Username: ${GREEN}${grafana_user}${NC}"
        echo -e "    Password: ${GREEN}${grafana_pass}${NC}"
        echo ""
    fi

    if [[ "$INSTALL_LITELLM" == "true" ]]; then
        local litellm_key=$(grep LITELLM_MASTER_KEY "$ENV_FILE" | cut -d'=' -f2)
        echo -e "  ${WHITE}LiteLLM API Key:${NC} ${GREEN}${litellm_key}${NC}"
        echo ""
    fi

    # Display data locations
    echo -e "${WHITE}💾 Data Locations:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Configuration: ${BLUE}${CONFIG_DIR}${NC}"
    echo -e "  Environment:   ${BLUE}${ENV_FILE}${NC}"
    echo -e "  Data:          ${BLUE}${DATA_DIR}${NC}"
    echo -e "  Logs:          ${BLUE}${LOG_FILE}${NC}"
    echo ""

    # Management commands
    echo -e "${WHITE}🛠️  Management Commands:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  View logs:        ${YELLOW}docker-compose logs -f [service]${NC}"
    echo -e "  Stop services:    ${YELLOW}docker-compose stop${NC}"
    echo -e "  Start services:   ${YELLOW}docker-compose start${NC}"
    echo -e "  Restart services: ${YELLOW}docker-compose restart${NC}"
    echo -e "  Remove all:       ${YELLOW}docker-compose down -v${NC}"
    echo ""

    if [[ "$INSTALL_OLLAMA" == "true" ]]; then
        echo -e "${WHITE}🤖 Ollama Commands:${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  List models:   ${YELLOW}docker exec platform_ollama ollama list${NC}"
        echo -e "  Pull model:    ${YELLOW}docker exec platform_ollama ollama pull <model>${NC}"
        echo -e "  Remove model:  ${YELLOW}docker exec platform_ollama ollama rm <model>${NC}"
        echo ""
    fi

    # Next steps
    echo -e "${WHITE}📋 Next Steps:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  1. Access services using the URLs above"
    echo -e "  2. Configure integrations in your preferred tools"
    echo -e "  3. Set up workflows in N8N (if installed)"
    echo -e "  4. Review logs: ${YELLOW}tail -f ${LOG_FILE}${NC}"
    echo ""

    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  For support: https://github.com/yourusername/ai-platform      ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

################################################################################
# Service Deployment
################################################################################

deploy_services() {
    print_header "DEPLOYING SERVICES"

    cd "$PROJECT_ROOT"

    print_step "Starting Docker Compose services..."
    if docker-compose up -d; then
        print_success "All services started"
    else
        print_error "Failed to start services"
        exit 1
    fi

    echo ""
    print_info "Waiting for services to initialize (30 seconds)..."
    sleep 30

    # Check service health
    check_service_health

    # Download Ollama models if requested
    if [[ "$INSTALL_OLLAMA" == "true" ]] && [[ -n "$OLLAMA_MODELS" ]]; then
        download_ollama_models
    fi
}

################################################################################
# Backup Functions
################################################################################

create_backup() {
    print_header "CREATING BACKUP"

    local backup_dir="$PROJECT_ROOT/backups"
    local backup_file="backup_$(date +%Y%m%d_%H%M%S).tar.gz"

    mkdir -p "$backup_dir"

    print_step "Backing up configuration and data..."

    tar -czf "$backup_dir/$backup_file" \
        -C "$PROJECT_ROOT" \
        config \
        docker-compose.yml \
        2>/dev/null || true

    print_success "Backup created: $backup_dir/$backup_file"
}

################################################################################
# Main Installation Function
################################################################################

main() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi

    # Display header
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║              AI Platform Automation Setup                        ║
║              Version 1.1.0-COMPLETE                              ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    print_info "Starting installation process..."
    echo ""

    # Installation steps
    check_prerequisites
    install_docker
    configure_network
    select_services

    # Configure Ollama models if selected
    if [[ "$INSTALL_OLLAMA" == "true" ]]; then
        select_ollama_models
    fi

    # Configure LLM providers if AI services selected
    if [[ "$INSTALL_AI_SERVICES" == "true" ]] || [[ "$INSTALL_LITELLM" == "true" ]]; then
        configure_llm_providers
    fi

    # Generate configuration files
    generate_env_file
    generate_config_files
    generate_docker_compose

    # Create backup before deployment
    if [[ -f "$PROJECT_ROOT/docker-compose.yml" ]]; then
        if prompt_yes_no "Create backup of existing configuration?"; then
            create_backup
        fi
    fi

    # Deploy services
    deploy_services

    # Display final summary
    display_summary

    print_success "Installation complete!"
}

################################################################################
# Script Entry Point
################################################################################

# Trap errors
trap 'print_error "An error occurred. Check $LOG_FILE for details."; exit 1' ERR

# Start logging
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

# Run main function
main "$@"
