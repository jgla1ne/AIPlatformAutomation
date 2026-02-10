#!/bin/bash
################################################################################
# AI Platform Automation Setup Script
# Version: 1.0.2
# Description: Interactive setup for AI development platform with Docker
################################################################################

set -euo pipefail

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly CONFIG_DIR="$PROJECT_ROOT/config"
readonly ENV_FILE="$CONFIG_DIR/.env"
readonly DOCKER_COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"

# Logging
readonly LOG_FILE="$PROJECT_ROOT/setup.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

################################################################################
# Utility Functions
################################################################################

print_banner() {
    echo -e "${CYAN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║         AI PLATFORM AUTOMATION - SYSTEM SETUP                     ║
║         Version 1.0.2                                             ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_section() {
    local title="$1"
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}${title}${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

prompt_user() {
    local prompt="$1"
    local default="$2"
    local response
    
    if [[ -n "$default" ]]; then
        read -p "$(echo -e ${CYAN}${prompt}${NC} [${default}]: )" response
        echo "${response:-$default}"
    else
        read -p "$(echo -e ${CYAN}${prompt}${NC}: )" response
        echo "$response"
    fi
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local response
    
    while true; do
        read -p "$(echo -e ${CYAN}${prompt}${NC} [y/n] (default: ${default}): )" response
        response="${response:-$default}"
        case "$response" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) print_warning "Please answer yes or no." ;;
        esac
    done
}

generate_random_password() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
}

################################################################################
# System Prerequisites
################################################################################

check_prerequisites() {
    print_section "Checking System Prerequisites"
    
    local missing_deps=()
    
    # Check required commands
    local required_commands=("docker" "docker-compose" "git" "curl" "openssl")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
            print_error "$cmd is not installed"
        else
            print_success "$cmd is installed"
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_info "Please install missing dependencies and run this script again"
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running"
        exit 1
    fi
    print_success "Docker daemon is running"
    
    # Check disk space (minimum 20GB free)
    local available_space=$(df -BG "$PROJECT_ROOT" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $available_space -lt 20 ]]; then
        print_warning "Low disk space: ${available_space}GB available (20GB+ recommended)"
    else
        print_success "Sufficient disk space: ${available_space}GB available"
    fi
}

install_docker() {
    print_section "Docker Installation"
    
    if command -v docker &> /dev/null; then
        print_success "Docker is already installed"
        docker --version
        return 0
    fi
    
    print_info "Installing Docker..."
    
    # Detect OS
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
    else
        print_error "Cannot detect operating system"
        exit 1
    fi
    
    case "$OS" in
        ubuntu|debian)
            apt-get update
            apt-get install -y ca-certificates curl gnupg lsb-release
            
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS $(lsb_release -cs) stable" | \
                tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        centos|rhel|fedora)
            yum install -y yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            systemctl start docker
            systemctl enable docker
            ;;
        *)
            print_error "Unsupported operating system: $OS"
            exit 1
            ;;
    esac
    
    # Add current user to docker group
    if [[ -n "${SUDO_USER:-}" ]]; then
        usermod -aG docker "$SUDO_USER"
        print_success "Added $SUDO_USER to docker group"
    fi
    
    print_success "Docker installed successfully"
}

################################################################################
# Network Configuration
################################################################################

configure_network() {
    print_section "Network Configuration"
    
    # Network mode selection
    echo "Select network configuration mode:"
    echo "1) Domain-based (Recommended for production)"
    echo "2) IP-based (Simple setup)"
    echo ""
    
    local network_mode
    while true; do
        read -p "$(echo -e ${CYAN}Enter choice [1-2]:${NC} )" network_mode
        case "$network_mode" in
            1|2) break ;;
            *) print_warning "Invalid choice. Please enter 1 or 2." ;;
        esac
    done
    
    if [[ "$network_mode" == "1" ]]; then
        NETWORK_MODE="domain"
        DOMAIN=$(prompt_user "Enter your domain name" "example.com")
        USE_HTTPS=$(prompt_yes_no "Enable HTTPS with Let's Encrypt?" "y" && echo "true" || echo "false")
        
        if [[ "$USE_HTTPS" == "true" ]]; then
            LETSENCRYPT_EMAIL=$(prompt_user "Enter email for Let's Encrypt" "")
        fi
        
        # Service subdomains
        N8N_SUBDOMAIN=$(prompt_user "N8N subdomain" "n8n")
        FLOWISE_SUBDOMAIN=$(prompt_user "Flowise subdomain" "flowise")
        DIFY_SUBDOMAIN=$(prompt_user "Dify subdomain" "dify")
        LANGFUSE_SUBDOMAIN=$(prompt_user "LangFuse subdomain" "langfuse")
        OPENWEBUI_SUBDOMAIN=$(prompt_user "Open WebUI subdomain" "chat")
        ANYTHINGLLM_SUBDOMAIN=$(prompt_user "AnythingLLM subdomain" "anything")
        LITELLM_SUBDOMAIN=$(prompt_user "LiteLLM subdomain" "litellm")
        OPENCLAW_SUBDOMAIN=$(prompt_user "OpenClaw subdomain" "openclaw")
        
    else
        NETWORK_MODE="ip"
        SERVER_IP=$(prompt_user "Enter server IP address" "$(hostname -I | awk '{print $1}')")
        USE_HTTPS="false"
        
        # Service ports
        N8N_PORT=$(prompt_user "N8N port" "5678")
        FLOWISE_PORT=$(prompt_user "Flowise port" "3000")
        DIFY_PORT=$(prompt_user "Dify port" "3001")
        LANGFUSE_PORT=$(prompt_user "LangFuse port" "3002")
        OPENWEBUI_PORT=$(prompt_user "Open WebUI port" "8080")
        ANYTHINGLLM_PORT=$(prompt_user "AnythingLLM port" "3003")
        LITELLM_PORT=$(prompt_user "LiteLLM port" "4000")
        OPENCLAW_PORT=$(prompt_user "OpenClaw port" "3004")
    fi
    
    print_success "Network configuration completed"
}

################################################################################
# Service Selection - 3 Platform Structure
################################################################################

select_services() {
    print_section "Service Selection"
    
    echo -e "${WHITE}Select services to install (grouped by platform):${NC}"
    echo ""
    
    # Platform 1: Automation & Workflows
    echo -e "${MAGENTA}═══ Platform 1: Automation & Workflows ═══${NC}"
    INSTALL_N8N=$(prompt_yes_no "Install N8N (Workflow Automation)?" "y" && echo "true" || echo "false")
    INSTALL_FLOWISE=$(prompt_yes_no "Install Flowise (Visual AI Chains)?" "y" && echo "true" || echo "false")
    echo ""
    
    # Platform 2: AI Development & Monitoring
    echo -e "${MAGENTA}═══ Platform 2: AI Development & Monitoring ═══${NC}"
    INSTALL_DIFY=$(prompt_yes_no "Install Dify (LLM App Development)?" "y" && echo "true" || echo "false")
    INSTALL_LANGFUSE=$(prompt_yes_no "Install LangFuse (LLM Observability)?" "y" && echo "true" || echo "false")
    echo ""
    
    # Platform 3: User Interfaces
    echo -e "${MAGENTA}═══ Platform 3: Chat Interfaces ═══${NC}"
    INSTALL_OPENWEBUI=$(prompt_yes_no "Install Open WebUI (ChatGPT-like Interface)?" "y" && echo "true" || echo "false")
    INSTALL_ANYTHINGLLM=$(prompt_yes_no "Install AnythingLLM (Document Chat)?" "y" && echo "true" || echo "false")
    INSTALL_OPENCLAW=$(prompt_yes_no "Install OpenClaw (AI Assistant)?" "y" && echo "true" || echo "false")
    echo ""
    
    # Core Services
    echo -e "${MAGENTA}═══ Core Services (Recommended) ═══${NC}"
    INSTALL_LITELLM=$(prompt_yes_no "Install LiteLLM (Unified LLM Gateway)?" "y" && echo "true" || echo "false")
    INSTALL_OLLAMA=$(prompt_yes_no "Install Ollama (Local LLM Runtime)?" "y" && echo "true" || echo "false")
    echo ""
    
    print_success "Service selection completed"
}

################################################################################
# LLM Configuration
################################################################################

configure_llm_providers() {
    print_section "LLM Provider Configuration"
    
    # OpenAI
    if prompt_yes_no "Configure OpenAI?" "y"; then
        OPENAI_API_KEY=$(prompt_user "Enter OpenAI API key" "")
        OPENAI_MODELS="gpt-4o,gpt-4o-mini,gpt-4-turbo,gpt-3.5-turbo"
        print_success "OpenAI configured with models: $OPENAI_MODELS"
    fi
    
    # Anthropic
    if prompt_yes_no "Configure Anthropic (Claude)?" "y"; then
        ANTHROPIC_API_KEY=$(prompt_user "Enter Anthropic API key" "")
        ANTHROPIC_MODELS="claude-3-5-sonnet-20241022,claude-3-5-haiku-20241022,claude-3-opus-20240229"
        print_success "Anthropic configured with models: $ANTHROPIC_MODELS"
    fi
    
    # Google Gemini
    if prompt_yes_no "Configure Google Gemini?" "y"; then
        GEMINI_API_KEY=$(prompt_user "Enter Google Gemini API key" "")
        GEMINI_MODELS="gemini-2.0-flash-exp,gemini-1.5-pro-latest,gemini-1.5-flash-latest"
        print_success "Gemini configured with models: $GEMINI_MODELS"
    fi
    
    # OpenRouter with dynamic model discovery
    if prompt_yes_no "Configure OpenRouter?" "y"; then
        OPENROUTER_API_KEY=$(prompt_user "Enter OpenRouter API key" "")
        
        print_info "Fetching available OpenRouter models..."
        local openrouter_models=$(curl -s https://openrouter.ai/api/v1/models \
            -H "Authorization: Bearer $OPENROUTER_API_KEY" | \
            jq -r '.data[].id' | head -20 | tr '\n' ',')
        
        if [[ -n "$openrouter_models" ]]; then
            OPENROUTER_MODELS="${openrouter_models%,}"
            print_success "OpenRouter configured with $(echo $OPENROUTER_MODELS | tr ',' '\n' | wc -l) models"
            print_info "Top models: $(echo $OPENROUTER_MODELS | cut -d',' -f1-3)"
        else
            print_warning "Could not fetch models, using defaults"
            OPENROUTER_MODELS="openai/gpt-4,anthropic/claude-3-opus,google/gemini-pro"
        fi
    fi
    
    # Ollama local models
    if [[ "$INSTALL_OLLAMA" == "true" ]]; then
        print_info "Ollama will be configured for local models"
        OLLAMA_MODELS=$(prompt_user "Enter Ollama models to pull (comma-separated)" "llama3.2,mistral,codellama")
    fi
    
    # LiteLLM Routing Strategy
    if [[ "$INSTALL_LITELLM" == "true" ]]; then
        echo ""
        echo -e "${WHITE}LiteLLM Routing Strategy:${NC}"
        echo "1) usage-based-routing (Recommended: Cost-optimized, local for simple, cloud for complex)"
        echo "2) simple-shuffle (Random selection)"
        echo "3) least-busy (Load balancing)"
        echo "4) latency-based-routing (Performance-optimized)"
        echo ""
        
        local routing_choice
        while true; do
            read -p "$(echo -e ${CYAN}Select routing strategy [1-4]:${NC} )" routing_choice
            case "$routing_choice" in
                1) LITELLM_ROUTING_STRATEGY="usage-based-routing"; break ;;
                2) LITELLM_ROUTING_STRATEGY="simple-shuffle"; break ;;
                3) LITELLM_ROUTING_STRATEGY="least-busy"; break ;;
                4) LITELLM_ROUTING_STRATEGY="latency-based-routing"; break ;;
                *) print_warning "Invalid choice. Please enter 1-4." ;;
            esac
        done
        
        print_success "LiteLLM routing strategy: $LITELLM_ROUTING_STRATEGY"
        print_info "This will route simple queries to local models and complex queries to cloud providers"
    fi
}

################################################################################
# Integration Configuration
################################################################################

configure_integrations() {
    print_section "Integration Configuration"
    
    # Google Drive
    if prompt_yes_no "Configure Google Drive integration?" "n"; then
        print_info "Google Drive OAuth setup required"
        GOOGLE_CLIENT_ID=$(prompt_user "Enter Google Client ID" "")
        GOOGLE_CLIENT_SECRET=$(prompt_user "Enter Google Client Secret" "")
        GOOGLE_REDIRECT_URI=$(prompt_user "Enter OAuth Redirect URI" "http://localhost:5678/oauth/callback")
        print_success "Google Drive configured"
    fi
    
    # Signal
    if prompt_yes_no "Configure Signal integration?" "n"; then
        SIGNAL_PHONE_NUMBER=$(prompt_user "Enter Signal phone number (with country code)" "")
        print_success "Signal configured (you'll need to link device)"
    fi
    
    # Email (SMTP)
    if prompt_yes_no "Configure email (SMTP)?" "n"; then
        SMTP_HOST=$(prompt_user "SMTP host" "smtp.gmail.com")
        SMTP_PORT=$(prompt_user "SMTP port" "587")
        SMTP_USER=$(prompt_user "SMTP username" "")
        SMTP_PASSWORD=$(prompt_user "SMTP password" "")
        SMTP_FROM=$(prompt_user "From email address" "$SMTP_USER")
        print_success "SMTP configured"
    fi
}

################################################################################
# Database Configuration
################################################################################

configure_databases() {
    print_section "Database Configuration"
    
    # PostgreSQL
    POSTGRES_USER="aiplatform"
    POSTGRES_PASSWORD=$(generate_random_password 32)
    POSTGRES_DB="aiplatform"
    
    print_info "PostgreSQL credentials:"
    echo "  User: $POSTGRES_USER"
    echo "  Password: $POSTGRES_PASSWORD"
    echo "  Database: $POSTGRES_DB"
    
    # Redis
    REDIS_PASSWORD=$(generate_random_password 32)
    print_info "Redis password: $REDIS_PASSWORD"
    
    # Qdrant (Vector DB)
    QDRANT_API_KEY=$(generate_random_password 32)
    print_info "Qdrant API key: $QDRANT_API_KEY"
    
    print_success "Database configuration completed"
}

################################################################################
# Generate Configuration Files
################################################################################

generate_env_file() {
    print_section "Generating Configuration Files"
    
    mkdir -p "$CONFIG_DIR"
    
    cat > "$ENV_FILE" << EOF
################################################################################
# AI Platform Configuration
# Generated: $(date)
# Version: 1.0.2
################################################################################

# Network Configuration
NETWORK_MODE=$NETWORK_MODE
${DOMAIN:+DOMAIN=$DOMAIN}
${SERVER_IP:+SERVER_IP=$SERVER_IP}
USE_HTTPS=$USE_HTTPS
${LETSENCRYPT_EMAIL:+LETSENCRYPT_EMAIL=$LETSENCRYPT_EMAIL}

# Service URLs/Ports
${N8N_SUBDOMAIN:+N8N_SUBDOMAIN=$N8N_SUBDOMAIN}
${N8N_PORT:+N8N_PORT=$N8N_PORT}
${FLOWISE_SUBDOMAIN:+FLOWISE_SUBDOMAIN=$FLOWISE_SUBDOMAIN}
${FLOWISE_PORT:+FLOWISE_PORT=$FLOWISE_PORT}
${DIFY_SUBDOMAIN:+DIFY_SUBDOMAIN=$DIFY_SUBDOMAIN}
${DIFY_PORT:+DIFY_PORT=$DIFY_PORT}
${LANGFUSE_SUBDOMAIN:+LANGFUSE_SUBDOMAIN=$LANGFUSE_SUBDOMAIN}
${LANGFUSE_PORT:+LANGFUSE_PORT=$LANGFUSE_PORT}
${OPENWEBUI_SUBDOMAIN:+OPENWEBUI_SUBDOMAIN=$OPENWEBUI_SUBDOMAIN}
${OPENWEBUI_PORT:+OPENWEBUI_PORT=$OPENWEBUI_PORT}
${ANYTHINGLLM_SUBDOMAIN:+ANYTHINGLLM_SUBDOMAIN=$ANYTHINGLLM_SUBDOMAIN}
${ANYTHINGLLM_PORT:+ANYTHINGLLM_PORT=$ANYTHINGLLM_PORT}
${LITELLM_SUBDOMAIN:+LITELLM_SUBDOMAIN=$LITELLM_SUBDOMAIN}
${LITELLM_PORT:+LITELLM_PORT=$LITELLM_PORT}
${OPENCLAW_SUBDOMAIN:+OPENCLAW_SUBDOMAIN=$OPENCLAW_SUBDOMAIN}
${OPENCLAW_PORT:+OPENCLAW_PORT=$OPENCLAW_PORT}

# Service Installation Flags
INSTALL_N8N=$INSTALL_N8N
INSTALL_FLOWISE=$INSTALL_FLOWISE
INSTALL_DIFY=$INSTALL_DIFY
INSTALL_LANGFUSE=$INSTALL_LANGFUSE
INSTALL_OPENWEBUI=$INSTALL_OPENWEBUI
INSTALL_ANYTHINGLLM=$INSTALL_ANYTHINGLLM
INSTALL_LITELLM=$INSTALL_LITELLM
INSTALL_OLLAMA=$INSTALL_OLLAMA
INSTALL_OPENCLAW=$INSTALL_OPENCLAW

# Database Configuration
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=$POSTGRES_DB
REDIS_PASSWORD=$REDIS_PASSWORD
QDRANT_API_KEY=$QDRANT_API_KEY

# LLM Providers
${OPENAI_API_KEY:+OPENAI_API_KEY=$OPENAI_API_KEY}
${OPENAI_MODELS:+OPENAI_MODELS=$OPENAI_MODELS}
${ANTHROPIC_API_KEY:+ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY}
${ANTHROPIC_MODELS:+ANTHROPIC_MODELS=$ANTHROPIC_MODELS}
${GEMINI_API_KEY:+GEMINI_API_KEY=$GEMINI_API_KEY}
${GEMINI_MODELS:+GEMINI_MODELS=$GEMINI_MODELS}
${OPENROUTER_API_KEY:+OPENROUTER_API_KEY=$OPENROUTER_API_KEY}
${OPENROUTER_MODELS:+OPENROUTER_MODELS=$OPENROUTER_MODELS}
${OLLAMA_MODELS:+OLLAMA_MODELS=$OLLAMA_MODELS}

# LiteLLM Configuration
${LITELLM_ROUTING_STRATEGY:+LITELLM_ROUTING_STRATEGY=$LITELLM_ROUTING_STRATEGY}

# Integrations
${GOOGLE_CLIENT_ID:+GOOGLE_CLIENT_ID=$GOOGLE_CLIENT_ID}
${GOOGLE_CLIENT_SECRET:+GOOGLE_CLIENT_SECRET=$GOOGLE_CLIENT_SECRET}
${GOOGLE_REDIRECT_URI:+GOOGLE_REDIRECT_URI=$GOOGLE_REDIRECT_URI}
${SIGNAL_PHONE_NUMBER:+SIGNAL_PHONE_NUMBER=$SIGNAL_PHONE_NUMBER}
${SMTP_HOST:+SMTP_HOST=$SMTP_HOST}
${SMTP_PORT:+SMTP_PORT=$SMTP_PORT}
${SMTP_USER:+SMTP_USER=$SMTP_USER}
${SMTP_PASSWORD:+SMTP_PASSWORD=$SMTP_PASSWORD}
${SMTP_FROM:+SMTP_FROM=$SMTP_FROM}

# Generated Secrets
N8N_ENCRYPTION_KEY=$(generate_random_password 32)
FLOWISE_SECRET_KEY=$(generate_random_password 32)
DIFY_SECRET_KEY=$(generate_random_password 64)
LANGFUSE_SECRET=$(generate_random_password 32)
ANYTHINGLLM_JWT_SECRET=$(generate_random_password 32)
LITELLM_MASTER_KEY=$(generate_random_password 32)

EOF

    chmod 600 "$ENV_FILE"
    print_success "Configuration file created: $ENV_FILE"
}

generate_litellm_config() {
    if [[ "$INSTALL_LITELLM" != "true" ]]; then
        return 0
    fi
    
    print_info "Generating LiteLLM configuration..."
    
    local litellm_config="$CONFIG_DIR/litellm-config.yaml"
    
    cat > "$litellm_config" << 'EOF'
model_list:
EOF

    # Add configured models
    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        IFS=',' read -ra MODELS <<< "$OPENAI_MODELS"
        for model in "${MODELS[@]}"; do
            cat >> "$litellm_config" << EOF
  - model_name: openai/$model
    litellm_params:
      model: $model
      api_key: \${OPENAI_API_KEY}
EOF
        done
    fi
    
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        IFS=',' read -ra MODELS <<< "$ANTHROPIC_MODELS"
        for model in "${MODELS[@]}"; do
            cat >> "$litellm_config" << EOF
  - model_name: anthropic/$model
    litellm_params:
      model: $model
      api_key: \${ANTHROPIC_API_KEY}
EOF
        done
    fi
    
    if [[ -n "${GEMINI_API_KEY:-}" ]]; then
        IFS=',' read -ra MODELS <<< "$GEMINI_MODELS"
        for model in "${MODELS[@]}"; do
            cat >> "$litellm_config" << EOF
  - model_name: gemini/$model
    litellm_params:
      model: $model
      api_key: \${GEMINI_API_KEY}
EOF
        done
    fi
    
    if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
        IFS=',' read -ra MODELS <<< "$OPENROUTER_MODELS"
        for model in "${MODELS[@]}"; do
            cat >> "$litellm_config" << EOF
  - model_name: openrouter/$model
    litellm_params:
      model: openrouter/$model
      api_key: \${OPENROUTER_API_KEY}
      api_base: https://openrouter.ai/api/v1
EOF
        done
    fi
    
    if [[ "$INSTALL_OLLAMA" == "true" ]]; then
        IFS=',' read -ra MODELS <<< "$OLLAMA_MODELS"
        for model in "${MODELS[@]}"; do
            cat >> "$litellm_config" << EOF
  - model_name: ollama/$model
    litellm_params:
      model: ollama/$model
      api_base: http://ollama:11434
EOF
        done
    fi
    
    # Add routing strategy
    cat >> "$litellm_config" << EOF

router_settings:
  routing_strategy: ${LITELLM_ROUTING_STRATEGY}
  fallbacks:
    - [ollama/*, openai/gpt-4o-mini]
    - [openai/*, anthropic/claude-3-5-haiku-20241022]
  
litellm_settings:
  success_callback: ["langfuse"]
  failure_callback: ["langfuse"]
EOF

    print_success "LiteLLM configuration created: $litellm_config"
}

################################################################################
# Service URLs Generation
################################################################################

generate_service_urls() {
    print_section "Generating Service URLs"
    
    local urls_file="$PROJECT_ROOT/service-urls.txt"
    
    cat > "$urls_file" << EOF
################################################################################
# AI Platform Service URLs
# Generated: $(date)
################################################################################

EOF

    if [[ "$NETWORK_MODE" == "domain" ]]; then
        local protocol="http"
        [[ "$USE_HTTPS" == "true" ]] && protocol="https"
        
        [[ "$INSTALL_N8N" == "true" ]] && echo "N8N:         ${protocol}://${N8N_SUBDOMAIN}.${DOMAIN}" >> "$urls_file"
        [[ "$INSTALL_FLOWISE" == "true" ]] && echo "Flowise:     ${protocol}://${FLOWISE_SUBDOMAIN}.${DOMAIN}" >> "$urls_file"
        [[ "$INSTALL_DIFY" == "true" ]] && echo "Dify:        ${protocol}://${DIFY_SUBDOMAIN}.${DOMAIN}" >> "$urls_file"
        [[ "$INSTALL_LANGFUSE" == "true" ]] && echo "LangFuse:    ${protocol}://${LANGFUSE_SUBDOMAIN}.${DOMAIN}" >> "$urls_file"
        [[ "$INSTALL_OPENWEBUI" == "true" ]] && echo "Open WebUI:  ${protocol}://${OPENWEBUI_SUBDOMAIN}.${DOMAIN}" >> "$urls_file"
        [[ "$INSTALL_ANYTHINGLLM" == "true" ]] && echo "AnythingLLM: ${protocol}://${ANYTHINGLLM_SUBDOMAIN}.${DOMAIN}" >> "$urls_file"
        [[ "$INSTALL_LITELLM" == "true" ]] && echo "LiteLLM:     ${protocol}://${LITELLM_SUBDOMAIN}.${DOMAIN}" >> "$urls_file"
        [[ "$INSTALL_OPENCLAW" == "true" ]] && echo "OpenClaw:    ${protocol}://${OPENCLAW_SUBDOMAIN}.${DOMAIN}" >> "$urls_file"
    else
        [[ "$INSTALL_N8N" == "true" ]] && echo "N8N:         http://${SERVER_IP}:${N8N_PORT}" >> "$urls_file"
        [[ "$INSTALL_FLOWISE" == "true" ]] && echo "Flowise:     http://${SERVER_IP}:${FLOWISE_PORT}" >> "$urls_file"
        [[ "$INSTALL_DIFY" == "true" ]] && echo "Dify:        http://${SERVER_IP}:${DIFY_PORT}" >> "$urls_file"
        [[ "$INSTALL_LANGFUSE" == "true" ]] && echo "LangFuse:    http://${SERVER_IP}:${LANGFUSE_PORT}" >> "$urls_file"
        [[ "$INSTALL_OPENWEBUI" == "true" ]] && echo "Open WebUI:  http://${SERVER_IP}:${OPENWEBUI_PORT}" >> "$urls_file"
        [[ "$INSTALL_ANYTHINGLLM" == "true" ]] && echo "AnythingLLM: http://${SERVER_IP}:${ANYTHINGLLM_PORT}" >> "$urls_file"
        [[ "$INSTALL_LITELLM" == "true" ]] && echo "LiteLLM:     http://${SERVER_IP}:${LITELLM_PORT}" >> "$urls_file"
        [[ "$INSTALL_OPENCLAW" == "true" ]] && echo "OpenClaw:    http://${SERVER_IP}:${OPENCLAW_PORT}" >> "$urls_file"
    fi
    
    cat >> "$urls_file" << EOF

################################################################################
# Database Connections
################################################################################

PostgreSQL:  postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:5432/${POSTGRES_DB}
Redis:       redis://:${REDIS_PASSWORD}@localhost:6379
Qdrant:      http://localhost:6333 (API Key: ${QDRANT_API_KEY})

EOF

    print_success "Service URLs saved to: $urls_file"
}

################################################################################
# Summary Display
################################################################################

display_summary() {
    print_section "Configuration Summary"
    
    echo -e "${WHITE}Network Configuration:${NC}"
    echo "  Mode: $NETWORK_MODE"
    if [[ "$NETWORK_MODE" == "domain" ]]; then
        echo "  Domain: $DOMAIN"
        echo "  HTTPS: $USE_HTTPS"
    else
        echo "  Server IP: $SERVER_IP"
    fi
    echo ""
    
    echo -e "${WHITE}Installed Services:${NC}"
    [[ "$INSTALL_N8N" == "true" ]] && echo "  ✓ N8N (Workflow Automation)"
    [[ "$INSTALL_FLOWISE" == "true" ]] && echo "  ✓ Flowise (Visual AI Chains)"
    [[ "$INSTALL_DIFY" == "true" ]] && echo "  ✓ Dify (LLM App Development)"
    [[ "$INSTALL_LANGFUSE" == "true" ]] && echo "  ✓ LangFuse (LLM Observability)"
    [[ "$INSTALL_OPENWEBUI" == "true" ]] && echo "  ✓ Open WebUI (Chat Interface)"
    [[ "$INSTALL_ANYTHINGLLM" == "true" ]] && echo "  ✓ AnythingLLM (Document Chat)"
    [[ "$INSTALL_LITELLM" == "true" ]] && echo "  ✓ LiteLLM (Unified Gateway)"
    [[ "$INSTALL_OLLAMA" == "true" ]] && echo "  ✓ Ollama (Local LLM)"
    [[ "$INSTALL_OPENCLAW" == "true" ]] && echo "  ✓ OpenClaw (AI Assistant)"
    echo ""
    
    echo -e "${WHITE}LLM Providers Configured:${NC}"
    [[ -n "${OPENAI_API_KEY:-}" ]] && echo "  ✓ OpenAI ($OPENAI_MODELS)"
    [[ -n "${ANTHROPIC_API_KEY:-}" ]] && echo "  ✓ Anthropic ($ANTHROPIC_MODELS)"
    [[ -n "${GEMINI_API_KEY:-}" ]] && echo "  ✓ Google Gemini ($GEMINI_MODELS)"
    [[ -n "${OPENROUTER_API_KEY:-}" ]] && echo "  ✓ OpenRouter ($(echo $OPENROUTER_MODELS | tr ',' '\n' | wc -l) models)"
    [[ "$INSTALL_OLLAMA" == "true" ]] && echo "  ✓ Ollama Local ($OLLAMA_MODELS)"
    echo ""
    
    echo -e "${WHITE}LiteLLM Routing:${NC}"
    [[ -n "${LITELLM_ROUTING_STRATEGY:-}" ]] && echo "  Strategy: $LITELLM_ROUTING_STRATEGY"
    echo "  Simple queries → Local models (Ollama)"
    echo "  Complex queries → Cloud providers"
    echo ""
    
    echo -e "${WHITE}Database Credentials:${NC}"
    echo "  PostgreSQL User: $POSTGRES_USER"
    echo "  PostgreSQL Password: $POSTGRES_PASSWORD"
    echo "  Redis Password: $REDIS_PASSWORD"
    echo "  Qdrant API Key: $QDRANT_API_KEY"
    echo ""
    
    echo -e "${WHITE}Service URLs:${NC}"
    cat "$PROJECT_ROOT/service-urls.txt" | grep -v "^#" | grep -v "^$"
    echo ""
    
    echo -e "${YELLOW}⚠ Important:${NC}"
    echo "  • Configuration saved to: $ENV_FILE"
    echo "  • Service URLs saved to: $PROJECT_ROOT/service-urls.txt"
    echo "  • Keep these credentials secure!"
    echo "  • Run script 2 (2-generate-compose.sh) to create Docker Compose configuration"
    echo ""
}

################################################################################
# Main Execution
################################################################################

main() {
    print_banner
    
    check_root
    check_prerequisites
    install_docker
    
    configure_network
    select_services
    configure_llm_providers
    configure_integrations
    configure_databases
    
    generate_env_file
    generate_litellm_config
    generate_service_urls
    
    display_summary
    
    print_success "System setup completed successfully!"
    print_info "Next step: Run ./scripts/2-generate-compose.sh to create Docker Compose configuration"
}

# Run main function
main "$@"

