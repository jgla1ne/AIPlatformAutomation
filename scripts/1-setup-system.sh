#!/bin/bash

################################################################################
# Script: 1-setup-system.sh
# Description: Interactive system setup and configuration for AI Platform
# Version: 3.0.0
# Features: 27-step interactive configuration with full customization
################################################################################

set -euo pipefail
IFS=$'\n\t'

################################################################################
# CONFIGURATION
################################################################################

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOG_DIR="${PROJECT_ROOT}/logs"
readonly LOG_FILE="${LOG_DIR}/1-setup-system_$(date +%Y%m%d_%H%M%S).log"
readonly CONFIG_FILE="${PROJECT_ROOT}/.env"
readonly BACKUP_DIR="${PROJECT_ROOT}/backups/$(date +%Y%m%d_%H%M%S)"
readonly TEMP_CONFIG="${PROJECT_ROOT}/.env.tmp"

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR_GENERAL=1
readonly EXIT_ERROR_PREREQ=2
readonly EXIT_ERROR_USER_CANCEL=3

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# Configuration storage
declare -A CONFIG_VALUES

################################################################################
# LOGGING AND DISPLAY FUNCTIONS
################################################################################

init_logging() {
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"
    exec > >(tee -a "$LOG_FILE")
    exec 2>&1
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date +"%Y-%m-%d %H:%M:%S") - $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date +"%Y-%m-%d %H:%M:%S") - $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date +"%Y-%m-%d %H:%M:%S") - $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date +"%Y-%m-%d %H:%M:%S") - $*" >&2
}

print_header() {
    local title="$1"
    local width=80
    echo
    echo -e "${CYAN}╔$(printf '═%.0s' $(seq 1 $((width-2))))╗${NC}"
    printf "${CYAN}║${NC}${BOLD}%-$((width-2))s${NC}${CYAN}║${NC}\n" " $title"
    echo -e "${CYAN}╚$(printf '═%.0s' $(seq 1 $((width-2))))╝${NC}"
    echo
}

print_step() {
    local step="$1"
    local total="$2"
    local description="$3"
    echo
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}${BOLD}Step $step of $total:${NC} ${CYAN}$description${NC}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
}

print_box() {
    local text="$1"
    local color="${2:-$WHITE}"
    echo -e "${color}┌─────────────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${color}│${NC} $text"
    echo -e "${color}└─────────────────────────────────────────────────────────────────────────────┘${NC}"
}
################################################################################
# INPUT FUNCTIONS
################################################################################

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local response

    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    while true; do
        read -r -p "$prompt" response
        response="${response:-$default}"
        case "$response" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

prompt_input() {
    local prompt="$1"
    local default="$2"
    local secret="${3:-false}"
    local response

    if [[ -n "$default" ]]; then
        prompt="$prompt [$default]: "
    else
        prompt="$prompt: "
    fi

    if [[ "$secret" == "true" ]]; then
        read -r -s -p "$prompt" response
        echo
    else
        read -r -p "$prompt" response
    fi

    echo "${response:-$default}"
}

prompt_choice() {
    local prompt="$1"
    shift
    local options=("$@")
    local choice

    echo "$prompt"
    for i in "${!options[@]}"; do
        echo "  $((i+1)). ${options[$i]}"
    done

    while true; do
        read -r -p "Enter choice [1-${#options[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "${#options[@]}" ]]; then
            echo "${options[$((choice-1))]}"
            return 0
        fi
        echo "Invalid choice. Please enter a number between 1 and ${#options[@]}."
    done
}

generate_password() {
    local length="${1:-32}"
    openssl rand -base64 48 | tr -d "=+/" | cut -c1-"$length"
}

generate_token() {
    local length="${1:-64}"
    openssl rand -hex "$length"
}
################################################################################
# PRIVILEGE CHECK
################################################################################

check_privileges() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run with sudo or as root"
        exit "$EXIT_ERROR_PREREQ"
    fi

    if [[ -n "${SUDO_USER:-}" ]]; then
        CONFIG_VALUES[ACTUAL_USER]="$SUDO_USER"
        CONFIG_VALUES[ACTUAL_HOME]=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    else
        CONFIG_VALUES[ACTUAL_USER]="root"
        CONFIG_VALUES[ACTUAL_HOME]="/root"
    fi

    log_info "Running as root, actual user: ${CONFIG_VALUES[ACTUAL_USER]}"
}

################################################################################
# SYSTEM REQUIREMENTS CHECK
################################################################################

validate_system() {
    log_info "Validating system requirements..."

    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot determine OS version"
        return 1
    fi

    source /etc/os-release
    CONFIG_VALUES[OS_NAME]="$NAME"
    CONFIG_VALUES[OS_VERSION]="$VERSION_ID"

    log_info "Operating System: $NAME $VERSION_ID"

    # Check disk space
    local available_gb
    available_gb=$(df -BG "$PROJECT_ROOT" | awk 'NR==2 {print $4}' | sed 's/G//')
    CONFIG_VALUES[DISK_AVAILABLE_GB]="$available_gb"

    if [[ $available_gb -lt 20 ]]; then
        log_error "Insufficient disk space. At least 20GB required, ${available_gb}GB available"
        return 1
    fi

    # Check memory
    local memory_gb
    memory_gb=$(free -g | awk '/^Mem:/{print $2}')
    CONFIG_VALUES[MEMORY_GB]="$memory_gb"

    if [[ $memory_gb -lt 4 ]]; then
        log_warn "Low memory detected: ${memory_gb}GB (Recommended: 8GB+)"
    fi

    # Check required commands
    local missing_commands=()
    for cmd in curl wget git jq openssl; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_warn "Missing commands: ${missing_commands[*]}"
    fi

    log_success "System validation completed"
}
################################################################################
# INTERACTIVE CONFIGURATION - STEPS 1-5
################################################################################

# Step 1: Welcome and Overview
step_01_welcome() {
    print_step 1 27 "Welcome and Overview"

    print_header "AI Platform Automation - Interactive Setup"

    cat << EOF
${BOLD}Welcome to the AI Platform Setup Wizard!${NC}

This interactive setup will guide you through configuring your AI platform
installation. The process includes:

  • System configuration and Docker setup
  • Service selection (AI models, databases, tools)
  • Security and authentication configuration
  • Network and proxy settings
  • Resource allocation
  • Backup and monitoring setup

${YELLOW}⏱  Estimated time: 10-15 minutes${NC}
${YELLOW}📋 You'll be asked ~27 configuration questions${NC}

${BOLD}Before we begin:${NC}
  ✓ Ensure you have sudo/root access
  ✓ Have any API keys or credentials ready
  ✓ Know your network configuration
  ✓ Decide which services you want to install

EOF

    if ! prompt_yes_no "Ready to begin setup?" "y"; then
        log_info "Setup cancelled by user"
        exit "$EXIT_ERROR_USER_CANCEL"
    fi
}

# Step 2: Installation Type
step_02_installation_type() {
    print_step 2 27 "Installation Type"

    cat << EOF
Select your installation type:

  ${BOLD}1. Minimal${NC} - Core AI services only (Ollama + Open WebUI)
     Disk: ~10GB | Memory: 4GB | Services: 2

  ${BOLD}2. Standard${NC} - AI services + automation (+ n8n)
     Disk: ~25GB | Memory: 8GB | Services: 5

  ${BOLD}3. Full${NC} - Complete stack with all features
     Disk: ~50GB | Memory: 16GB | Services: 10+

  ${BOLD}4. Custom${NC} - Choose individual services
     Disk: Varies | Memory: Varies | Services: Your choice

EOF

    local install_type
    install_type=$(prompt_choice "Select installation type:" "Minimal" "Standard" "Full" "Custom")
    CONFIG_VALUES[INSTALL_TYPE]="$install_type"

    log_info "Selected installation type: $install_type"
}

# Step 3: Project Configuration
step_03_project_config() {
    print_step 3 27 "Project Configuration"

    CONFIG_VALUES[PROJECT_NAME]=$(prompt_input "Enter project name" "ai-platform")
    CONFIG_VALUES[ENVIRONMENT]=$(prompt_choice "Select environment:" "production" "staging" "development")
    CONFIG_VALUES[PROJECT_DESCRIPTION]=$(prompt_input "Project description (optional)" "AI Platform Deployment")

    log_info "Project: ${CONFIG_VALUES[PROJECT_NAME]} (${CONFIG_VALUES[ENVIRONMENT]})"
}

# Step 4: Docker Configuration
step_04_docker_setup() {
    print_step 4 27 "Docker Configuration"

    if command -v docker &> /dev/null; then
        local docker_version
        docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
        log_info "Docker already installed: $docker_version"

        if prompt_yes_no "Reinstall/Update Docker?" "n"; then
            CONFIG_VALUES[DOCKER_INSTALL]="reinstall"
        else
            CONFIG_VALUES[DOCKER_INSTALL]="skip"
        fi
    else
        log_info "Docker not found - will be installed"
        CONFIG_VALUES[DOCKER_INSTALL]="install"
    fi

    if [[ "${CONFIG_VALUES[DOCKER_INSTALL]}" != "skip" ]]; then
        CONFIG_VALUES[DOCKER_DATA_ROOT]=$(prompt_input "Docker data directory" "/var/lib/docker")
        CONFIG_VALUES[DOCKER_LOG_MAX_SIZE]=$(prompt_input "Docker log max size" "10m")
        CONFIG_VALUES[DOCKER_LOG_MAX_FILES]=$(prompt_input "Docker log max files" "3")
    fi
}

# Step 5: Network Configuration
step_05_network_config() {
    print_step 5 27 "Network Configuration"

    CONFIG_VALUES[NETWORK_NAME]=$(prompt_input "Docker network name" "ai-platform-network")
    CONFIG_VALUES[NETWORK_SUBNET]=$(prompt_input "Network subnet" "172.28.0.0/16")
    CONFIG_VALUES[NETWORK_GATEWAY]=$(prompt_input "Network gateway" "172.28.0.1")

    if prompt_yes_no "Enable IPv6?" "n"; then
        CONFIG_VALUES[ENABLE_IPV6]="true"
        CONFIG_VALUES[IPV6_SUBNET]=$(prompt_input "IPv6 subnet" "fd00::/64")
    else
        CONFIG_VALUES[ENABLE_IPV6]="false"
    fi
}
################################################################################
# INTERACTIVE CONFIGURATION - STEPS 6-10
################################################################################

# Step 6: Service Selection - AI Models
step_06_ai_services() {
    print_step 6 27 "AI Model Services"

    local should_install="n"
    if [[ "${CONFIG_VALUES[INSTALL_TYPE]}" == "Custom" ]]; then
        prompt_yes_no "Install Ollama (Local LLM runtime)?" "y" && should_install="y"
    elif [[ "${CONFIG_VALUES[INSTALL_TYPE]}" != "Minimal" ]] || prompt_yes_no "Install Ollama (Local LLM runtime)?" "y"; then
        should_install="y"
    fi

    if [[ "$should_install" == "y" ]]; then
        CONFIG_VALUES[INSTALL_OLLAMA]="true"
        CONFIG_VALUES[OLLAMA_VERSION]=$(prompt_input "Ollama version" "latest")
        CONFIG_VALUES[OLLAMA_PORT]=$(prompt_input "Ollama port" "11434")
        CONFIG_VALUES[OLLAMA_HOST]=$(prompt_input "Ollama host" "0.0.0.0")

        echo
        echo "Select AI models to pre-download (space-separated):"
        echo "Available: llama3.2 llama3.1 llama2 codellama mistral mixtral phi gemma qwen deepseek"
        CONFIG_VALUES[OLLAMA_MODELS]=$(prompt_input "Models" "llama3.2 codellama")

        CONFIG_VALUES[OLLAMA_MEMORY_LIMIT]=$(prompt_input "Ollama memory limit" "8g")
        CONFIG_VALUES[OLLAMA_CPU_LIMIT]=$(prompt_input "Ollama CPU limit (cores)" "4")
    else
        CONFIG_VALUES[INSTALL_OLLAMA]="false"
    fi
}

# Step 7: Service Selection - Web UI
step_07_webui_service() {
    print_step 7 27 "Web Interface"

    local should_install="n"
    if [[ "${CONFIG_VALUES[INSTALL_TYPE]}" == "Custom" ]]; then
        prompt_yes_no "Install Open WebUI?" "y" && should_install="y"
    elif [[ "${CONFIG_VALUES[INSTALL_TYPE]}" != "Minimal" ]] || prompt_yes_no "Install Open WebUI?" "y"; then
        should_install="y"
    fi

    if [[ "$should_install" == "y" ]]; then
        CONFIG_VALUES[INSTALL_WEBUI]="true"
        CONFIG_VALUES[WEBUI_VERSION]=$(prompt_input "Open WebUI version" "latest")
        CONFIG_VALUES[WEBUI_PORT]=$(prompt_input "Open WebUI port" "3000")
        CONFIG_VALUES[WEBUI_NAME]=$(prompt_input "WebUI instance name" "AI Platform")
        CONFIG_VALUES[WEBUI_MEMORY_LIMIT]=$(prompt_input "WebUI memory limit" "2g")

        if prompt_yes_no "Enable WebUI authentication?" "y"; then
            CONFIG_VALUES[WEBUI_AUTH_ENABLED]="true"
            CONFIG_VALUES[WEBUI_DEFAULT_USER]=$(prompt_input "Default admin username" "admin")
            CONFIG_VALUES[WEBUI_DEFAULT_EMAIL]=$(prompt_input "Default admin email" "admin@localhost")
        else
            CONFIG_VALUES[WEBUI_AUTH_ENABLED]="false"
        fi
    else
        CONFIG_VALUES[INSTALL_WEBUI]="false"
    fi
}

# Step 8: Database Selection
step_08_database_selection() {
    print_step 8 27 "Database Services"

    cat << EOF
Select databases to install (you can choose multiple):

  1. ${BOLD}PostgreSQL${NC} - Relational database (Recommended)
  2. ${BOLD}MySQL/MariaDB${NC} - Alternative relational database
  3. ${BOLD}MongoDB${NC} - NoSQL document database
  4. ${BOLD}Redis${NC} - In-memory cache/database (Recommended)
  5. ${BOLD}None${NC} - Skip database installation

EOF

    CONFIG_VALUES[INSTALL_DATABASES]=""

    if [[ "${CONFIG_VALUES[INSTALL_TYPE]}" != "Minimal" ]] || prompt_yes_no "Install PostgreSQL?" "y"; then
        CONFIG_VALUES[INSTALL_POSTGRES]="true"
        CONFIG_VALUES[INSTALL_DATABASES]+="postgres "
    else
        CONFIG_VALUES[INSTALL_POSTGRES]="false"
    fi

    if prompt_yes_no "Install MySQL/MariaDB?" "n"; then
        CONFIG_VALUES[INSTALL_MYSQL]="true"
        CONFIG_VALUES[INSTALL_DATABASES]+="mysql "
    else
        CONFIG_VALUES[INSTALL_MYSQL]="false"
    fi

    if prompt_yes_no "Install MongoDB?" "n"; then
        CONFIG_VALUES[INSTALL_MONGODB]="true"
        CONFIG_VALUES[INSTALL_DATABASES]+="mongodb "
    else
        CONFIG_VALUES[INSTALL_MONGODB]="false"
    fi

    if [[ "${CONFIG_VALUES[INSTALL_TYPE]}" != "Minimal" ]] || prompt_yes_no "Install Redis?" "y"; then
        CONFIG_VALUES[INSTALL_REDIS]="true"
        CONFIG_VALUES[INSTALL_DATABASES]+="redis "
    else
        CONFIG_VALUES[INSTALL_REDIS]="false"
    fi
}

# Step 9: PostgreSQL Configuration
step_09_postgres_config() {
    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
        print_step 9 27 "PostgreSQL Configuration"

        CONFIG_VALUES[POSTGRES_VERSION]=$(prompt_input "PostgreSQL version" "16-alpine")
        CONFIG_VALUES[POSTGRES_PORT]=$(prompt_input "PostgreSQL port" "5432")
        CONFIG_VALUES[POSTGRES_DB]=$(prompt_input "Database name" "aiplatform")
        CONFIG_VALUES[POSTGRES_USER]=$(prompt_input "Database user" "aiplatform")

        if prompt_yes_no "Generate secure password automatically?" "y"; then
            CONFIG_VALUES[POSTGRES_PASSWORD]=$(generate_password 32)
            log_success "Generated secure PostgreSQL password"
        else
            CONFIG_VALUES[POSTGRES_PASSWORD]=$(prompt_input "Database password" "" "true")
        fi

        CONFIG_VALUES[POSTGRES_MEMORY_LIMIT]=$(prompt_input "PostgreSQL memory limit" "2g")
        CONFIG_VALUES[POSTGRES_MAX_CONNECTIONS]=$(prompt_input "Max connections" "100")
    else
        print_step 9 27 "PostgreSQL Configuration (Skipped)"
    fi
}

# Step 10: Redis Configuration
step_10_redis_config() {
    if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
        print_step 10 27 "Redis Configuration"

        CONFIG_VALUES[REDIS_VERSION]=$(prompt_input "Redis version" "7-alpine")
        CONFIG_VALUES[REDIS_PORT]=$(prompt_input "Redis port" "6379")

        if prompt_yes_no "Enable Redis authentication?" "y"; then
            if prompt_yes_no "Generate secure password automatically?" "y"; then
                CONFIG_VALUES[REDIS_PASSWORD]=$(generate_password 32)
                log_success "Generated secure Redis password"
            else
                CONFIG_VALUES[REDIS_PASSWORD]=$(prompt_input "Redis password" "" "true")
            fi
        else
            CONFIG_VALUES[REDIS_PASSWORD]=""
        fi

        CONFIG_VALUES[REDIS_MEMORY_LIMIT]=$(prompt_input "Redis memory limit" "1g")
        CONFIG_VALUES[REDIS_MAXMEMORY_POLICY]=$(prompt_choice "Eviction policy:" "allkeys-lru" "volatile-lru" "allkeys-lfu" "noeviction")
    else
        print_step 10 27 "Redis Configuration (Skipped)"
    fi
}
################################################################################
# INTERACTIVE CONFIGURATION - STEPS 11-15
################################################################################

# Step 11: Automation Services (n8n)
step_11_automation_services() {
    print_step 11 27 "Automation Services"

    local should_install="n"
    if [[ "${CONFIG_VALUES[INSTALL_TYPE]}" == "Standard" ]] || [[ "${CONFIG_VALUES[INSTALL_TYPE]}" == "Full" ]]; then
        should_install="y"
    elif [[ "${CONFIG_VALUES[INSTALL_TYPE]}" == "Custom" ]]; then
        prompt_yes_no "Install n8n (Workflow Automation)?" "n" && should_install="y"
    fi

    if [[ "$should_install" == "y" ]]; then
        CONFIG_VALUES[INSTALL_N8N]="true"
        CONFIG_VALUES[N8N_VERSION]=$(prompt_input "n8n version" "latest")
        CONFIG_VALUES[N8N_PORT]=$(prompt_input "n8n port" "5678")
        CONFIG_VALUES[N8N_HOST]=$(prompt_input "n8n host/domain" "localhost")
        CONFIG_VALUES[N8N_PROTOCOL]=$(prompt_choice "n8n protocol:" "http" "https")

        if prompt_yes_no "Generate n8n encryption key automatically?" "y"; then
            CONFIG_VALUES[N8N_ENCRYPTION_KEY]=$(generate_token 32)
            log_success "Generated n8n encryption key"
        else
            CONFIG_VALUES[N8N_ENCRYPTION_KEY]=$(prompt_input "n8n encryption key" "" "true")
        fi

        CONFIG_VALUES[N8N_MEMORY_LIMIT]=$(prompt_input "n8n memory limit" "2g")

        if prompt_yes_no "Enable n8n basic authentication?" "y"; then
            CONFIG_VALUES[N8N_BASIC_AUTH_ACTIVE]="true"
            CONFIG_VALUES[N8N_BASIC_AUTH_USER]=$(prompt_input "n8n auth username" "admin")
            CONFIG_VALUES[N8N_BASIC_AUTH_PASSWORD]=$(prompt_input "n8n auth password" "" "true")
        else
            CONFIG_VALUES[N8N_BASIC_AUTH_ACTIVE]="false"
        fi
    else
        CONFIG_VALUES[INSTALL_N8N]="false"
    fi
}

# Step 12: Monitoring Services
step_12_monitoring_services() {
    print_step 12 27 "Monitoring & Observability"

    if [[ "${CONFIG_VALUES[INSTALL_TYPE]}" == "Full" ]] || prompt_yes_no "Install monitoring stack (Prometheus + Grafana)?" "n"; then
        CONFIG_VALUES[INSTALL_MONITORING]="true"

        # Prometheus
        CONFIG_VALUES[PROMETHEUS_VERSION]=$(prompt_input "Prometheus version" "latest")
        CONFIG_VALUES[PROMETHEUS_PORT]=$(prompt_input "Prometheus port" "9090")
        CONFIG_VALUES[PROMETHEUS_RETENTION]=$(prompt_input "Data retention period" "15d")
        CONFIG_VALUES[PROMETHEUS_MEMORY_LIMIT]=$(prompt_input "Prometheus memory limit" "2g")

        # Grafana
        CONFIG_VALUES[GRAFANA_VERSION]=$(prompt_input "Grafana version" "latest")
        CONFIG_VALUES[GRAFANA_PORT]=$(prompt_input "Grafana port" "3001")
        CONFIG_VALUES[GRAFANA_ADMIN_USER]=$(prompt_input "Grafana admin username" "admin")

        if prompt_yes_no "Generate Grafana admin password automatically?" "y"; then
            CONFIG_VALUES[GRAFANA_ADMIN_PASSWORD]=$(generate_password 24)
            log_success "Generated Grafana admin password"
        else
            CONFIG_VALUES[GRAFANA_ADMIN_PASSWORD]=$(prompt_input "Grafana admin password" "" "true")
        fi

        CONFIG_VALUES[GRAFANA_MEMORY_LIMIT]=$(prompt_input "Grafana memory limit" "1g")

        # Node Exporter
        if prompt_yes_no "Install Node Exporter (system metrics)?" "y"; then
            CONFIG_VALUES[INSTALL_NODE_EXPORTER]="true"
            CONFIG_VALUES[NODE_EXPORTER_PORT]=$(prompt_input "Node Exporter port" "9100")
        else
            CONFIG_VALUES[INSTALL_NODE_EXPORTER]="false"
        fi

        # cAdvisor
        if prompt_yes_no "Install cAdvisor (container metrics)?" "y"; then
            CONFIG_VALUES[INSTALL_CADVISOR]="true"
            CONFIG_VALUES[CADVISOR_PORT]=$(prompt_input "cAdvisor port" "8080")
        else
            CONFIG_VALUES[INSTALL_CADVISOR]="false"
        fi
    else
        CONFIG_VALUES[INSTALL_MONITORING]="false"
    fi
}

# Step 13: Reverse Proxy Configuration
step_13_proxy_config() {
    print_step 13 27 "Reverse Proxy Configuration"

    if prompt_yes_no "Install Nginx reverse proxy?" "n"; then
        CONFIG_VALUES[INSTALL_NGINX]="true"
        CONFIG_VALUES[NGINX_VERSION]=$(prompt_input "Nginx version" "alpine")
        CONFIG_VALUES[NGINX_HTTP_PORT]=$(prompt_input "Nginx HTTP port" "80")
        CONFIG_VALUES[NGINX_HTTPS_PORT]=$(prompt_input "Nginx HTTPS port" "443")

        if prompt_yes_no "Enable SSL/TLS?" "n"; then
            CONFIG_VALUES[NGINX_SSL_ENABLED]="true"
            CONFIG_VALUES[SSL_CERTIFICATE_PATH]=$(prompt_input "SSL certificate path" "/etc/nginx/ssl/cert.pem")
            CONFIG_VALUES[SSL_KEY_PATH]=$(prompt_input "SSL key path" "/etc/nginx/ssl/key.pem")

            if prompt_yes_no "Use Let's Encrypt for SSL?" "n"; then
                CONFIG_VALUES[USE_LETSENCRYPT]="true"
                CONFIG_VALUES[LETSENCRYPT_EMAIL]=$(prompt_input "Let's Encrypt email" "")
                CONFIG_VALUES[LETSENCRYPT_DOMAIN]=$(prompt_input "Domain name" "")
            else
                CONFIG_VALUES[USE_LETSENCRYPT]="false"
            fi
        else
            CONFIG_VALUES[NGINX_SSL_ENABLED]="false"
        fi

        CONFIG_VALUES[NGINX_MEMORY_LIMIT]=$(prompt_input "Nginx memory limit" "512m")
    else
        CONFIG_VALUES[INSTALL_NGINX]="false"
    fi
}

# Step 14: External Proxy Configuration
step_14_external_proxy() {
    print_step 14 27 "External Proxy Settings"

    if prompt_yes_no "Use external HTTP/HTTPS proxy?" "n"; then
        CONFIG_VALUES[USE_PROXY]="true"
        CONFIG_VALUES[HTTP_PROXY]=$(prompt_input "HTTP proxy URL (e.g., http://proxy:8080)" "")
        CONFIG_VALUES[HTTPS_PROXY]=$(prompt_input "HTTPS proxy URL" "${CONFIG_VALUES[HTTP_PROXY]}")
        CONFIG_VALUES[NO_PROXY]=$(prompt_input "No proxy for (comma-separated)" "localhost,127.0.0.1,.local")

        if prompt_yes_no "Does proxy require authentication?" "n"; then
            CONFIG_VALUES[PROXY_USER]=$(prompt_input "Proxy username" "")
            CONFIG_VALUES[PROXY_PASS]=$(prompt_input "Proxy password" "" "true")
        fi
    else
        CONFIG_VALUES[USE_PROXY]="false"
    fi
}

# Step 15: API Keys and External Services
step_15_api_keys() {
    print_step 15 27 "API Keys & External Services"

    cat << EOF
${BOLD}Configure API keys for external AI services (optional):${NC}

Many AI platforms offer APIs that can enhance your local setup:
  • OpenAI (GPT models)
  • Anthropic (Claude)
  • Google (Gemini)
  • Hugging Face (Model repository)
  • Stability AI (Image generation)

EOF

    if prompt_yes_no "Configure OpenAI API?" "n"; then
        CONFIG_VALUES[OPENAI_API_KEY]=$(prompt_input "OpenAI API Key" "" "true")
        CONFIG_VALUES[OPENAI_ORG_ID]=$(prompt_input "OpenAI Organization ID (optional)" "")
    fi

    if prompt_yes_no "Configure Anthropic API?" "n"; then
        CONFIG_VALUES[ANTHROPIC_API_KEY]=$(prompt_input "Anthropic API Key" "" "true")
    fi

    if prompt_yes_no "Configure Google AI API?" "n"; then
        CONFIG_VALUES[GOOGLE_API_KEY]=$(prompt_input "Google AI API Key" "" "true")
    fi

    if prompt_yes_no "Configure Hugging Face?" "n"; then
        CONFIG_VALUES[HUGGINGFACE_TOKEN]=$(prompt_input "Hugging Face Token" "" "true")
    fi

    if prompt_yes_no "Configure Stability AI?" "n"; then
        CONFIG_VALUES[STABILITY_API_KEY]=$(prompt_input "Stability AI API Key" "" "true")
    fi
}
################################################################################
# INTERACTIVE CONFIGURATION - STEPS 16-20
################################################################################

# Step 16: Vector Database
step_16_vector_database() {
    print_step 16 27 "Vector Database"

    cat << EOF
${BOLD}Vector databases store embeddings for RAG and semantic search.${NC}

Available options:
  1. ${BOLD}ChromaDB${NC} - Lightweight, easy to use
  2. ${BOLD}Qdrant${NC} - Production-ready, scalable
  3. ${BOLD}Weaviate${NC} - Feature-rich, cloud-native
  4. ${BOLD}Milvus${NC} - High-performance, enterprise-grade
  5. ${BOLD}None${NC} - Skip vector database

EOF

    if [[ "${CONFIG_VALUES[INSTALL_TYPE]}" == "Full" ]] || prompt_yes_no "Install a vector database?" "n"; then
        local vector_db
        vector_db= $ (prompt_choice "Select vector database:" "ChromaDB" "Qdrant" "Weaviate" "Milvus" "None")

        case " $ vector_db" in
            "ChromaDB")
                CONFIG_VALUES[INSTALL_CHROMADB]="true"
                CONFIG_VALUES[CHROMADB_VERSION]= $ (prompt_input "ChromaDB version" "latest")
                CONFIG_VALUES[CHROMADB_PORT]= $ (prompt_input "ChromaDB port" "8000")
                CONFIG_VALUES[CHROMADB_MEMORY_LIMIT]= $ (prompt_input "ChromaDB memory limit" "2g")
                ;;
            "Qdrant")
                CONFIG_VALUES[INSTALL_QDRANT]="true"
                CONFIG_VALUES[QDRANT_VERSION]= $ (prompt_input "Qdrant version" "latest")
                CONFIG_VALUES[QDRANT_PORT]= $ (prompt_input "Qdrant port" "6333")
                CONFIG_VALUES[QDRANT_GRPC_PORT]= $ (prompt_input "Qdrant gRPC port" "6334")
                CONFIG_VALUES[QDRANT_MEMORY_LIMIT]= $ (prompt_input "Qdrant memory limit" "4g")

                if prompt_yes_no "Enable Qdrant API key authentication?" "y"; then
                    CONFIG_VALUES[QDRANT_API_KEY]= $ (generate_token 32)
                    log_success "Generated Qdrant API key"
                fi
                ;;
            "Weaviate")
                CONFIG_VALUES[INSTALL_WEAVIATE]="true"
                CONFIG_VALUES[WEAVIATE_VERSION]= $ (prompt_input "Weaviate version" "latest")
                CONFIG_VALUES[WEAVIATE_PORT]= $ (prompt_input "Weaviate port" "8080")
                CONFIG_VALUES[WEAVIATE_GRPC_PORT]= $ (prompt_input "Weaviate gRPC port" "50051")
                CONFIG_VALUES[WEAVIATE_MEMORY_LIMIT]= $ (prompt_input "Weaviate memory limit" "4g")
                ;;
            "Milvus")
                CONFIG_VALUES[INSTALL_MILVUS]="true"
                CONFIG_VALUES[MILVUS_VERSION]= $ (prompt_input "Milvus version" "latest")
                CONFIG_VALUES[MILVUS_PORT]= $ (prompt_input "Milvus port" "19530")
		CONFIG_VALUES[MILVUS_MEMORY_LIMIT]=$(prompt_input "Milvus memory limit" "4g")
                CONFIG_VALUES[MILVUS_METRIC_PORT]=$(prompt_input "Milvus metrics port" "9091")
                ;;
            "None")
                log_info "Skipping vector database installation"
                ;;
        esac
    fi
}

# Step 17: Storage Configuration
step_17_storage_config() {
    print_step 17 27 "Storage & Volume Configuration"

    cat << EOF
${BOLD}Configure persistent storage for your AI platform.${NC}

Options:
  • Local volumes (Docker volumes on host)
  • Custom mount paths (for NFS, shared storage, etc.)

EOF

    CONFIG_VALUES[STORAGE_TYPE]=$(prompt_choice "Storage type:" "docker-volumes" "custom-paths")

    if [[ "${CONFIG_VALUES[STORAGE_TYPE]}" == "custom-paths" ]]; then
        CONFIG_VALUES[DATA_ROOT]=$(prompt_input "Data root path" "/data/aiplatform")
        CONFIG_VALUES[OLLAMA_MODELS_PATH]=$(prompt_input "Ollama models path" "${CONFIG_VALUES[DATA_ROOT]}/ollama/models")
        CONFIG_VALUES[POSTGRES_DATA_PATH]=$(prompt_input "PostgreSQL data path" "${CONFIG_VALUES[DATA_ROOT]}/postgres")
        CONFIG_VALUES[REDIS_DATA_PATH]=$(prompt_input "Redis data path" "${CONFIG_VALUES[DATA_ROOT]}/redis")
        CONFIG_VALUES[N8N_DATA_PATH]=$(prompt_input "n8n data path" "${CONFIG_VALUES[DATA_ROOT]}/n8n")
        CONFIG_VALUES[WEBUI_DATA_PATH]=$(prompt_input "Open WebUI data path" "${CONFIG_VALUES[DATA_ROOT]}/webui")

        log_info "Creating storage directories..."
        mkdir -p "${CONFIG_VALUES[DATA_ROOT]}"
        [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]] && mkdir -p "${CONFIG_VALUES[OLLAMA_MODELS_PATH]}"
        [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]] && mkdir -p "${CONFIG_VALUES[POSTGRES_DATA_PATH]}"
        [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]] && mkdir -p "${CONFIG_VALUES[REDIS_DATA_PATH]}"
        [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]] && mkdir -p "${CONFIG_VALUES[N8N_DATA_PATH]}"
        [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]] && mkdir -p "${CONFIG_VALUES[WEBUI_DATA_PATH]}"
    else
        CONFIG_VALUES[STORAGE_TYPE]="docker-volumes"
        log_info "Using Docker managed volumes"
    fi

    # Backup configuration
    if prompt_yes_no "Configure automatic backups?" "n"; then
        CONFIG_VALUES[ENABLE_BACKUPS]="true"
        CONFIG_VALUES[BACKUP_PATH]=$(prompt_input "Backup directory" "${PROJECT_ROOT}/backups")
        CONFIG_VALUES[BACKUP_RETENTION_DAYS]=$(prompt_input "Backup retention (days)" "7")
        CONFIG_VALUES[BACKUP_SCHEDULE]=$(prompt_input "Backup schedule (cron format)" "0 2 * * *")
        mkdir -p "${CONFIG_VALUES[BACKUP_PATH]}"
    else
        CONFIG_VALUES[ENABLE_BACKUPS]="false"
    fi
}

# Step 18: Network Configuration
step_18_network_config() {
    print_step 18 27 "Network Configuration"

    cat << EOF
${BOLD}Configure Docker networking for the platform.${NC}

Docker network modes:
  • ${BOLD}bridge${NC} - Isolated network (recommended)
  • ${BOLD}host${NC} - Use host network (better performance, less isolation)
  • ${BOLD}custom${NC} - Use existing network

EOF

    CONFIG_VALUES[NETWORK_MODE]=$(prompt_choice "Network mode:" "bridge" "host" "custom")

    if [[ "${CONFIG_VALUES[NETWORK_MODE]}" == "bridge" ]]; then
        CONFIG_VALUES[NETWORK_NAME]=$(prompt_input "Network name" "aiplatform_network")
        CONFIG_VALUES[NETWORK_SUBNET]=$(prompt_input "Network subnet (CIDR)" "172.28.0.0/16")
        CONFIG_VALUES[NETWORK_GATEWAY]=$(prompt_input "Network gateway" "172.28.0.1")
    elif [[ "${CONFIG_VALUES[NETWORK_MODE]}" == "custom" ]]; then
        CONFIG_VALUES[NETWORK_NAME]=$(prompt_input "Existing network name" "")
    fi

    # DNS Configuration
    if prompt_yes_no "Configure custom DNS servers?" "n"; then
        CONFIG_VALUES[USE_CUSTOM_DNS]="true"
        CONFIG_VALUES[DNS_SERVERS]=$(prompt_input "DNS servers (comma-separated)" "8.8.8.8,8.8.4.4")
    else
        CONFIG_VALUES[USE_CUSTOM_DNS]="false"
    fi

    # IP Whitelisting
    if prompt_yes_no "Configure IP whitelisting?" "n"; then
        CONFIG_VALUES[ENABLE_IP_WHITELIST]="true"
        CONFIG_VALUES[ALLOWED_IPS]=$(prompt_input "Allowed IPs (comma-separated, blank for all)" "")
    else
        CONFIG_VALUES[ENABLE_IP_WHITELIST]="false"
    fi
}

# Step 19: Resource Limits & Performance
step_19_resource_limits() {
    print_step 19 27 "Resource Limits & Performance"

    cat << EOF
${BOLD}Configure resource limits for containers.${NC}

Set CPU and memory limits to prevent resource exhaustion.
Leave blank to use defaults.

EOF

    # Global settings
    CONFIG_VALUES[ENABLE_RESOURCE_LIMITS]=$(prompt_yes_no "Enable resource limits?" "y" && echo "true" || echo "false")

    if [[ "${CONFIG_VALUES[ENABLE_RESOURCE_LIMITS]}" == "true" ]]; then
        cat << EOF

${BOLD}CPU Limits:${NC}
  • Use decimal values (e.g., 0.5 = 50% of one CPU core)
  • Use whole numbers (e.g., 2 = 2 CPU cores)

${BOLD}Memory Limits:${NC}
  • Use suffixes: m (MB), g (GB)
  • Examples: 512m, 2g, 4g

EOF

        # Ollama resources (most critical)
        if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
            log_info "Ollama resource limits:"
            CONFIG_VALUES[OLLAMA_CPU_LIMIT]=$(prompt_input "  CPU limit" "4")
            CONFIG_VALUES[OLLAMA_MEMORY_LIMIT]=$(prompt_input "  Memory limit" "8g")
            CONFIG_VALUES[OLLAMA_MEMORY_RESERVATION]=$(prompt_input "  Memory reservation" "4g")
        fi

        # Open WebUI resources
        if [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]]; then
            log_info "Open WebUI resource limits:"
            CONFIG_VALUES[WEBUI_CPU_LIMIT]=$(prompt_input "  CPU limit" "2")
            CONFIG_VALUES[WEBUI_MEMORY_LIMIT]=$(prompt_input "  Memory limit" "2g")
        fi

        # n8n resources
        if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
            log_info "n8n resource limits:"
            CONFIG_VALUES[N8N_CPU_LIMIT]=$(prompt_input "  CPU limit" "2")
            # Memory limit already set in step 11
        fi

        # Database resources
        if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
            log_info "PostgreSQL resource limits:"
            CONFIG_VALUES[POSTGRES_CPU_LIMIT]=$(prompt_input "  CPU limit" "2")
            # Memory limit already set in step 9
        fi

        if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
            log_info "Redis resource limits:"
            CONFIG_VALUES[REDIS_CPU_LIMIT]=$(prompt_input "  CPU limit" "1")
            # Memory limit already set in step 10
        fi
    fi

    # Restart policies
    CONFIG_VALUES[RESTART_POLICY]=$(prompt_choice "Container restart policy:" "unless-stopped" "always" "on-failure" "no")
}

# Step 20: Security Configuration
step_20_security_config() {
    print_step 20 27 "Security Configuration"

    cat << EOF
${BOLD}Configure security settings for the platform.${NC}

Security features:
  ✓ Authentication & Authorization
  ✓ Secret Management
  ✓ Network Security
  ✓ Access Control

EOF

    # JWT/Session secrets
    log_info "Generating security tokens..."
    CONFIG_VALUES[JWT_SECRET]=$(generate_token 64)
    CONFIG_VALUES[SESSION_SECRET]=$(generate_token 64)
    CONFIG_VALUES[ENCRYPTION_KEY]=$(generate_token 32)
    log_success "Generated security tokens"

    # CORS Configuration
    if prompt_yes_no "Configure CORS (Cross-Origin Resource Sharing)?" "n"; then
        CONFIG_VALUES[ENABLE_CORS]="true"
        CONFIG_VALUES[CORS_ORIGINS]=$(prompt_input "Allowed origins (comma-separated)" "*")
        CONFIG_VALUES[CORS_METHODS]=$(prompt_input "Allowed methods" "GET,POST,PUT,DELETE,OPTIONS")
    else
        CONFIG_VALUES[ENABLE_CORS]="false"
    fi

    # Rate limiting
    if prompt_yes_no "Enable rate limiting?" "y"; then
        CONFIG_VALUES[ENABLE_RATE_LIMIT]="true"
        CONFIG_VALUES[RATE_LIMIT_REQUESTS]=$(prompt_input "Max requests per window" "100")
        CONFIG_VALUES[RATE_LIMIT_WINDOW]=$(prompt_input "Time window (seconds)" "60")
    else
        CONFIG_VALUES[ENABLE_RATE_LIMIT]="false"
    fi

    # Security headers
    CONFIG_VALUES[ENABLE_SECURITY_HEADERS]=$(prompt_yes_no "Enable security headers (HSTS, CSP, etc.)?" "y" && echo "true" || echo "false")

    # Audit logging
    if prompt_yes_no "Enable audit logging?" "n"; then
        CONFIG_VALUES[ENABLE_AUDIT_LOG]="true"
        CONFIG_VALUES[AUDIT_LOG_PATH]=$(prompt_input "Audit log path" "${LOG_DIR}/audit.log")
        CONFIG_VALUES[AUDIT_LOG_LEVEL]=$(prompt_choice "Audit log level:" "info" "warn" "error" "debug")
    else
        CONFIG_VALUES[ENABLE_AUDIT_LOG]="false"
    fi

    # Firewall rules
    if prompt_yes_no "Configure UFW firewall rules?" "n"; then
        CONFIG_VALUES[CONFIGURE_FIREWALL]="true"
        log_warn "Firewall rules will be configured in system setup"
    else
        CONFIG_VALUES[CONFIGURE_FIREWALL]="false"
    fi
}
################################################################################
# INTERACTIVE CONFIGURATION - STEPS 21-25
################################################################################

# Step 21: Logging Configuration
step_21_logging_config() {
    print_step 21 27 "Logging Configuration"

    cat << EOF
${BOLD}Configure logging for all services.${NC}

Logging options:
  • Log level (debug, info, warn, error)
  • Log rotation
  • Centralized logging
  • Log
 • ${BOLD}Let's Encrypt${NC} - Free automated certificates
  • ${BOLD}Self-signed${NC} - For development/testing
  • ${BOLD}Custom${NC} - Use your own certificates
  • ${BOLD}None${NC} - HTTP only (not recommended for production)

EOF

    CONFIG_VALUES[ENABLE_SSL]=$(prompt_yes_no "Enable SSL/TLS?" "n" && echo "true" || echo "false")

    if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]]; then
        local ssl_type
        ssl_type=$(prompt_choice "SSL certificate type:" "letsencrypt" "self-signed" "custom" "none")
        CONFIG_VALUES[SSL_TYPE]="$ssl_type"

        case "$ssl_type" in
            "letsencrypt")
                log_info "Let's Encrypt configuration"
                CONFIG_VALUES[SSL_EMAIL]=$(prompt_input "Email for Let's Encrypt" "")
                CONFIG_VALUES[SSL_DOMAIN]=$(prompt_input "Domain name" "")
                CONFIG_VALUES[LETSENCRYPT_STAGING]=$(prompt_yes_no "Use staging environment? (for testing)" "n" && echo "true" || echo "false")

                # Install Certbot
                CONFIG_VALUES[INSTALL_CERTBOT]="true"
                CONFIG_VALUES[CERTBOT_AUTO_RENEW]=$(prompt_yes_no "Enable automatic renewal?" "y" && echo "true" || echo "false")

                if [[ "${CONFIG_VALUES[CERTBOT_AUTO_RENEW]}" == "true" ]]; then
                    CONFIG_VALUES[CERTBOT_RENEW_HOOK]=$(prompt_input "Post-renewal hook command" "docker-compose restart nginx")
                fi
                ;;

            "self-signed")
                log_info "Self-signed certificate configuration"
                CONFIG_VALUES[SSL_COUNTRY]=$(prompt_input "Country code (2 letters)" "US")
                CONFIG_VALUES[SSL_STATE]=$(prompt_input "State/Province" "")
                CONFIG_VALUES[SSL_CITY]=$(prompt_input "City" "")
                CONFIG_VALUES[SSL_ORG]=$(prompt_input "Organization" "AI Platform")
                CONFIG_VALUES[SSL_COMMON_NAME]=$(prompt_input "Common Name (domain/IP)" "localhost")
                CONFIG_VALUES[SSL_DAYS]=$(prompt_input "Certificate validity (days)" "365")

                log_info "Generating self-signed certificate..."
                mkdir -p "${PROJECT_ROOT}/ssl"
                openssl req -x509 -nodes -days "${CONFIG_VALUES[SSL_DAYS]}" \
                    -newkey rsa:2048 \
                    -keyout "${PROJECT_ROOT}/ssl/privkey.pem" \
                    -out "${PROJECT_ROOT}/ssl/fullchain.pem" \
                    -subj "/C=${CONFIG_VALUES[SSL_COUNTRY]}/ST=${CONFIG_VALUES[SSL_STATE]}/L=${CONFIG_VALUES[SSL_CITY]}/O=${CONFIG_VALUES[SSL_ORG]}/CN=${CONFIG_VALUES[SSL_COMMON_NAME]}" \
                    2>/dev/null

                if [[ $? -eq 0 ]]; then
                    log_success "Self-signed certificate generated"
                    CONFIG_VALUES[SSL_CERT_PATH]="${PROJECT_ROOT}/ssl/fullchain.pem"
                    CONFIG_VALUES[SSL_KEY_PATH]="${PROJECT_ROOT}/ssl/privkey.pem"
                else
                    log_error "Failed to generate self-signed certificate"
                fi
                ;;

            "custom")
                log_info "Custom certificate configuration"
                CONFIG_VALUES[SSL_CERT_PATH]=$(prompt_input "Certificate file path (.crt or .pem)" "")
                CONFIG_VALUES[SSL_KEY_PATH]=$(prompt_input "Private key file path (.key or .pem)" "")
                CONFIG_VALUES[SSL_CHAIN_PATH]=$(prompt_input "Chain file path (optional)" "")

                # Validate certificate files
                if [[ ! -f "${CONFIG_VALUES[SSL_CERT_PATH]}" ]]; then
                    log_error "Certificate file not found: ${CONFIG_VALUES[SSL_CERT_PATH]}"
                elif [[ ! -f "${CONFIG_VALUES[SSL_KEY_PATH]}" ]]; then
                    log_error "Private key file not found: ${CONFIG_VALUES[SSL_KEY_PATH]}"
                else
                    log_success "Certificate files validated"
                fi
                ;;

            "none")
                CONFIG_VALUES[ENABLE_SSL]="false"
                log_warn "SSL disabled - not recommended for production!"
                ;;
        esac

        # SSL configuration options
        if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]]; then
            CONFIG_VALUES[SSL_PROTOCOLS]=$(prompt_input "SSL protocols" "TLSv1.2 TLSv1.3")
            CONFIG_VALUES[SSL_CIPHERS]=$(prompt_input "SSL ciphers (leave empty for default)" "")
            CONFIG_VALUES[FORCE_HTTPS]=$(prompt_yes_no "Force HTTPS redirect?" "y" && echo "true" || echo "false")
            CONFIG_VALUES[HSTS_ENABLED]=$(prompt_yes_no "Enable HSTS?" "y" && echo "true" || echo "false")

            if [[ "${CONFIG_VALUES[HSTS_ENABLED]}" == "true" ]]; then
                CONFIG_VALUES[HSTS_MAX_AGE]=$(prompt_input "HSTS max-age (seconds)" "31536000")
            fi
        fi
    else
        log_warn "Proceeding without SSL - connections will be unencrypted"
    fi
}

# Step 25: Reverse Proxy Configuration
step_25_reverse_proxy() {
    print_step 25 27 "Reverse Proxy Configuration"

    cat << EOF
${BOLD}Configure reverse proxy for service routing.${NC}

A reverse proxy provides:
  • Single entry point for all services
  • SSL/TLS termination
  • Load balancing
  • Path-based routing

EOF

    if prompt_yes_no "Install reverse proxy (Nginx)?" "y"; then
        CONFIG_VALUES[INSTALL_NGINX]="true"
        CONFIG_VALUES[NGINX_VERSION]=$(prompt_input "Nginx version" "alpine")
        CONFIG_VALUES[NGINX_HTTP_PORT]=$(prompt_input "HTTP port" "80")
        CONFIG_VALUES[NGINX_HTTPS_PORT]=$(prompt_input "HTTPS port" "443")

        # Service routing
        log_info "Configure service routes:"

        if [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]]; then
            CONFIG_VALUES[WEBUI_PATH]=$(prompt_input "Open WebUI path" "/")
        fi

        if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
            CONFIG_VALUES[N8N_PATH]=$(prompt_input "n8n path" "/n8n")
        fi

        if [[ "${CONFIG_VALUES[INSTALL_GRAFANA]}" == "true" ]]; then
            CONFIG_VALUES[GRAFANA_PATH]=$(prompt_input "Grafana path" "/grafana")
        fi

        if [[ "${CONFIG_VALUES[INSTALL_UPTIME_KUMA]}" == "true" ]]; then
            CONFIG_VALUES[UPTIME_KUMA_PATH]=$(prompt_input "Uptime Kuma path" "/uptime")
        fi

        # Advanced Nginx options
        if prompt_yes_no "Configure advanced Nginx options?" "n"; then
            CONFIG_VALUES[NGINX_CLIENT_MAX_BODY_SIZE]=$(prompt_input "Max upload size" "100M")
            CONFIG_VALUES[NGINX_WORKER_PROCESSES]=$(prompt_input "Worker processes" "auto")
            CONFIG_VALUES[NGINX_WORKER_CONNECTIONS]=$(prompt_input "Worker connections" "1024")
            CONFIG_VALUES[NGINX_KEEPALIVE_TIMEOUT]=$(prompt_input "Keepalive timeout (seconds)" "65")
            CONFIG_VALUES[NGINX_GZIP]=$(prompt_yes_no "Enable gzip compression?" "y" && echo "on" || echo "off")
            CONFIG_VALUES[NGINX_RATE_LIMIT]=$(prompt_yes_no "Enable rate limiting?" "y" && echo "true" || echo "false")

            if [[ "${CONFIG_VALUES[NGINX_RATE_LIMIT]}" == "true" ]]; then
                CONFIG_VALUES[NGINX_RATE_LIMIT_ZONE]=$(prompt_input "Rate limit (req/s)" "10")
            fi
        fi

        # Generate Nginx config
        log_info "Nginx configuration will be generated during installation"
    else
        CONFIG_VALUES[INSTALL_NGINX]="false"
        log_info "Skipping reverse proxy - services will use direct ports"
    fi
}

# Step 26: Advanced Options
step_26_advanced_options() {
    print_step 26 27 "Advanced Options"

    cat << EOF
${BOLD}Configure advanced system options.${NC}

These options are for advanced users and specific use cases.

EOF

    if ! prompt_yes_no "Configure advanced options?" "n"; then
        log_info "Skipping advanced options"
        return
    fi

    # Docker network configuration
    log_info "Docker Network Configuration"
    CONFIG_VALUES[DOCKER_NETWORK_NAME]=$(prompt_input "Docker network name" "aiplatform_network")
    CONFIG_VALUES[DOCKER_NETWORK_DRIVER]=$(prompt_choice "Network driver:" "bridge" "overlay" "host")

    if [[ "${CONFIG_VALUES[DOCKER_NETWORK_DRIVER]}" == "bridge" ]]; then
        CONFIG_VALUES[DOCKER_NETWORK_SUBNET]=$(prompt_input "Network subnet" "172.28.0.0/16")
        CONFIG_VALUES[DOCKER_NETWORK_GATEWAY]=$(prompt_input "Network gateway" "172.28.0.1")
    fi

    # Container resource limits
    if prompt_yes_no "Set global container resource limits?" "n"; then
        CONFIG_VALUES[DEFAULT_CPU_LIMIT]=$(prompt_input "Default CPU limit (cores)" "2")
        CONFIG_VALUES[DEFAULT_MEMORY_LIMIT]=$(prompt_input "Default memory limit" "2g")
        CONFIG_VALUES[DEFAULT_MEMORY_RESERVATION]=$(prompt_input "Default memory reservation" "512m")
    fi

    # Docker Compose options
    log_info "Docker Compose Configuration"
    CONFIG_VALUES[COMPOSE_PROJECT_NAME]=$(prompt_input "Docker Compose project name" "aiplatform")
    CONFIG_VALUES[COMPOSE_FILE_VERSION]=$(prompt_input "Compose file version" "3.8")

    # Restart policies
    CONFIG_VALUES[DEFAULT_RESTART_POLICY]=$(prompt_choice "Default restart policy:" "unless-stopped" "always" "on-failure" "no")

    # Development options
    if prompt_yes_no "Enable development mode?" "n"; then
        CONFIG_VALUES[DEV_MODE]="true"
        CONFIG_VALUES[ENABLE_DEBUG]="true"
        CONFIG_VALUES[HOT_RELOAD]=$(prompt_yes_no "Enable hot reload?" "y" && echo "true" || echo "false")
        CONFIG_VALUES[EXPOSE_ALL_PORTS]=$(prompt_yes_no "Expose all service ports?" "y" && echo "true" || echo "false")
    else
        CONFIG_VALUES[DEV_MODE]="false"
        CONFIG_VALUES[ENABLE_DEBUG]="false"
    fi

    # API Gateway
    if prompt_yes_no "Setup API Gateway (Kong/Traefik)?" "n"; then
        local gateway_type
        gateway_type=$(prompt_choice "Select API Gateway:" "Kong" "Traefik" "None")

        case "$gateway_type" in
            "Kong")
                CONFIG_VALUES[INSTALL_KONG]="true"
                CONFIG_VALUES[KONG_VERSION]=$(prompt_input "Kong version" "latest")
                CONFIG_VALUES[KONG_ADMIN_PORT]=$(prompt_input "Kong admin port" "8001")
                CONFIG_VALUES[KONG_PROXY_PORT]=$(prompt_input "Kong proxy port" "8000")
                ;;
            "Traefik")
                CONFIG_VALUES[INSTALL_TRAEFIK]="true"
                CONFIG_VALUES[TRAEFIK_VERSION]=$(prompt_input "Traefik version" "latest")
                CONFIG_VALUES[TRAEFIK_DASHBOARD_PORT]=$(prompt_input "Traefik dashboard port" "8080")
                ;;
        esac
    fi

    # Custom environment variables
    if prompt_yes_no "Add custom environment variables?" "n"; then
        log_info "Enter custom variables (format: KEY=value, empty line to finish)"
        while true; do
            read -r -p "Variable: " custom_var
            [[ -z "$custom_var" ]] && break

            if [[ "$custom_var" =~ ^[A-Z_][A-Z0-9_]*=.+$ ]]; then
                CONFIG_VALUES[CUSTOM_ENV_VARS]+="$custom_var"$'\n'
                log_success "Added: $custom_var"
            else
                log_warn "Invalid format. Use: KEY=value"
            fi
        done
    fi

    # Feature flags
    log_info "Feature Flags"
    CONFIG_VALUES[ENABLE_EXPERIMENTAL]=$(prompt_yes_no "Enable experimental features?" "n" && echo "true" || echo "false")
    CONFIG_VALUES[ENABLE_TELEMETRY]=$(prompt_yes_no "Enable telemetry/analytics?" "n" && echo "true" || echo "false")
    CONFIG_VALUES[ENABLE_AUTO_UPDATE]=$(prompt_yes_no "Enable automatic updates?" "n" && echo "true" || echo "false")
}

# Step 27: Configuration Review & Confirmation
step_27_review_confirm() {
    print_step 27 27 "Configuration Review & Confirmation"

    cat << EOF
${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}
${BOLD}                  CONFIGURATION SUMMARY${NC}
${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}

EOF

    # System Configuration
    cat << EOF
${BOLD}${YELLOW}System Configuration:${NC}
  Installation Type: ${CONFIG_VALUES[INSTALL_TYPE]}
  Project Name: ${CONFIG_VALUES[PROJECT_NAME]}
  Environment: ${CONFIG_VALUES[ENVIRONMENT]}
  Installation Path: ${PROJECT_ROOT}

${BOLD}${YELLOW}Core Services:${NC}
EOF

    [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]] && echo "  ✓ Ollama (Port: ${CONFIG_VALUES[OLLAMA_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]] && echo "  ✓ Open WebUI (Port: ${CONFIG_VALUES[WEBUI_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]] && echo "  ✓ n8n (Port: ${CONFIG_VALUES[N8N_PORT]})"

    cat << EOF

${BOLD}${YELLOW}Database Services:${NC}
EOF

    [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]] && echo "  ✓ PostgreSQL (Port: ${CONFIG_VALUES[POSTGRES_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]] && echo "  ✓ Redis (Port: ${CONFIG_VALUES[REDIS_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_CHROMADB]}" == "true" ]] && echo "  ✓ ChromaDB (Port: ${CONFIG_VALUES[CHROMADB_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_QDRANT]}" == "true" ]] && echo "  ✓ Qdrant (Port: ${CONFIG_VALUES[QDRANT_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_WEAVIATE]}" == "true" ]] && echo "  ✓ Weaviate (Port: ${CONFIG_VALUES[WEAVIATE_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_MILVUS]}" == "true" ]] && echo "  ✓ Milvus (Port: ${CONFIG_VALUES[MILVUS_PORT]})"

    cat << EOF

${BOLD}${YELLOW}Monitoring & Management:${NC}
EOF

    [[ "${CONFIG_VALUES[INSTALL_PROMETHEUS]}" == "true" ]] && echo "  ✓ Prometheus (Port: ${CONFIG_VALUES[PROMETHEUS_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_GRAFANA]}" == "true" ]] && echo "  ✓ Grafana (Port: ${CONFIG_VALUES[GRAFANA_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_UPTIME_KUMA]}" == "true" ]] && echo "  ✓ Uptime Kuma (Port: ${CONFIG_VALUES[UPTIME_KUMA_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_PORTAINER]}" == "true" ]] && echo "  ✓ Portainer (Port: ${CONFIG_VALUES[PORTAINER_PORT]})"

    cat << EOF

${BOLD}${YELLOW}Infrastructure:${NC}
EOF

    [[ "${CONFIG_VALUES[INSTALL_NGINX]}" == "true" ]] && echo "  ✓ Nginx Reverse Proxy"
    [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]] && echo "  ✓ SSL/TLS (${CONFIG_VALUES[SSL_TYPE]})"
    [[ "${CONFIG_VALUES[ENABLE_BACKUPS]}" == "true" ]] && echo "  ✓ Automated Backups"
    [[ "${CONFIG_VALUES[ENABLE_MONITORING]}" == "true" ]] && echo "  ✓ System Monitoring"

    cat << EOF

${BOLD}${YELLOW}Storage:${NC}
  Storage Type: ${CONFIG_VALUES[STORAGE_TYPE]}
EOF

    if [[ "${CONFIG_VALUES[STORAGE_TYPE]}" == "custom-paths" ]]; then
        echo "  Data Root: ${CONFIG_VALUES[DATA_ROOT]}"
    fi

    if [[ "${CONFIG_VALUES[ENABLE_BACKUPS]}" == "true" ]]; then
        cat << EOF
  Backup Path: ${CONFIG_VALUES[BACKUP_PATH]}
  Backup Schedule: ${CONFIG_VALUES[BACKUP_SCHEDULE]:-Manual}
  Retention: ${CONFIG_VALUES[BACKUP_RETENTION_DAYS]} days
EOF
    fi

    cat << EOF

${BOLD}${YELLOW}Security:${NC}
  SSL/TLS: ${CONFIG_VALUES[ENABLE_SSL]:-false}
  Rate Limiting: ${CONFIG_VALUES[ENABLE_RATE_LIMIT]:-false}
  Firewall: ${CONFIG_VALUES[CONFIGURE_FIREWALL]:-false}
  Audit Logging: ${CONFIG_VALUES[ENABLE_AUDIT_LOG]:-false}

${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}

EOF

    # Save configuration preview
    local preview_file="${CONFIG_DIR}/config-preview.txt"
    {
        echo "AI Platform Configuration Summary"
        echo "Generated: $(date)"
        echo ""
        for key in "${!CONFIG_VALUES[@]}"; do
            # Mask sensitive values
            if [[ "$key" =~ PASSWORD|SECRET|KEY|TOKEN ]]; then
                echo "$key=********"
            else
                echo "$key=${CONFIG_VALUES[$key]}"
            fi
        done
    } > "$preview_file"

    log_info "Configuration preview saved to: $preview_file"

    echo ""
    if prompt_yes_no "${BOLD}Proceed with this configuration?${NC}" "y"; then
        log_success "Configuration confirmed!"
        return 0
    else
        log_warn "Configuration cancelled"
        if prompt_yes_no "Start configuration over?" "y"; then
            exec "$0" "$@"  # Restart script
        else
            exit 0
        fi
    fi
}
################################################################################
# CONFIGURATION FILE GENERATION
################################################################################

# Generate .env file
generate_env_file() {
    log_info "Generating .env file..."

    local env_file="${PROJECT_ROOT}/.env"
    local env_template="${SCRIPT_DIR}/templates/.env.template"

    # Backup existing .env if it exists
    if [[ -f "$env_file" ]]; then
        local backup_file="${env_file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$env_file" "$backup_file"
        log_info "Backed up existing .env to: $backup_file"
    fi

    # Create .env file
    {
        cat << 'EOF'
################################################################################
# AI PLATFORM CONFIGURATION
# Generated by install.sh
# Date: $(date)
################################################################################

EOF

        # System Configuration
        cat << EOF
#------------------------------------------------------------------------------
# SYSTEM CONFIGURATION
#------------------------------------------------------------------------------
PROJECT_NAME=${CONFIG_VALUES[PROJECT_NAME]}
ENVIRONMENT=${CONFIG_VALUES[ENVIRONMENT]}
INSTALL_TYPE=${CONFIG_VALUES[INSTALL_TYPE]}
TIMEZONE=${CONFIG_VALUES[TIMEZONE]}

EOF

        # Core Services
        if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
            cat << EOF
#------------------------------------------------------------------------------
# OLLAMA CONFIGURATION
#------------------------------------------------------------------------------
OLLAMA_ENABLED=true
OLLAMA_VERSION=${CONFIG_VALUES[OLLAMA_VERSION]}
OLLAMA_PORT=${CONFIG_VALUES[OLLAMA_PORT]}
OLLAMA_HOST=${CONFIG_VALUES[OLLAMA_HOST]}
OLLAMA_MODELS=${CONFIG_VALUES[OLLAMA_MODELS]}
OLLAMA_NUM_PARALLEL=${CONFIG_VALUES[OLLAMA_NUM_PARALLEL]}
OLLAMA_MAX_LOADED_MODELS=${CONFIG_VALUES[OLLAMA_MAX_LOADED_MODELS]}
OLLAMA_GPU_LAYERS=${CONFIG_VALUES[OLLAMA_GPU_LAYERS]}
OLLAMA_MEMORY_LIMIT=${CONFIG_VALUES[OLLAMA_MEMORY_LIMIT]}

EOF
        fi

        if [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]]; then
            cat << EOF
#------------------------------------------------------------------------------
# OPEN WEBUI CONFIGURATION
#------------------------------------------------------------------------------
WEBUI_ENABLED=true
WEBUI_VERSION=${CONFIG_VALUES[WEBUI_VERSION]}
WEBUI_PORT=${CONFIG_VALUES[WEBUI_PORT]}
WEBUI_NAME=${CONFIG_VALUES[WEBUI_NAME]}
WEBUI_URL=${CONFIG_VALUES[WEBUI_URL]}
WEBUI_SECRET_KEY=${CONFIG_VALUES[WEBUI_SECRET_KEY]}
OLLAMA_BASE_URL=http://ollama:${CONFIG_VALUES[OLLAMA_PORT]}

EOF
        fi

        # Database Configuration
        if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
            cat << EOF
#------------------------------------------------------------------------------
# POSTGRESQL CONFIGURATION
#------------------------------------------------------------------------------
POSTGRES_ENABLED=true
POSTGRES_VERSION=${CONFIG_VALUES[POSTGRES_VERSION]}
POSTGRES_PORT=${CONFIG_VALUES[POSTGRES_PORT]}
POSTGRES_DB=${CONFIG_VALUES[POSTGRES_DB]}
POSTGRES_USER=${CONFIG_VALUES[POSTGRES_USER]}
POSTGRES_PASSWORD=${CONFIG_VALUES[POSTGRES_PASSWORD]}
POSTGRES_MAX_CONNECTIONS=${CONFIG_VALUES[POSTGRES_MAX_CONNECTIONS]}
POSTGRES_SHARED_BUFFERS=${CONFIG_VALUES[POSTGRES_SHARED_BUFFERS]}

EOF
        fi

        if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
            cat << EOF
#------------------------------------------------------------------------------
# REDIS CONFIGURATION
#------------------------------------------------------------------------------
REDIS_ENABLED=true
REDIS_VERSION=${CONFIG_VALUES[REDIS_VERSION]}
REDIS_PORT=${CONFIG_VALUES[REDIS_PORT]}
REDIS_PASSWORD=${CONFIG_VALUES[REDIS_PASSWORD]}
REDIS_MAXMEMORY=${CONFIG_VALUES[REDIS_MAXMEMORY]}
REDIS_MAXMEMORY_POLICY=${CONFIG_VALUES[REDIS_MAXMEMORY_POLICY]}

EOF
        fi

        # Add all other configured services...
        # (Similar blocks for n8n, monitoring, vector databases, etc.)

        # Security
        cat << EOF
#------------------------------------------------------------------------------
# SECURITY CONFIGURATION
#------------------------------------------------------------------------------
JWT_SECRET=${CONFIG_VALUES[JWT_SECRET]}
SESSION_SECRET=${CONFIG_VALUES[SESSION_SECRET]}
ENCRYPTION_KEY=${CONFIG_VALUES[ENCRYPTION_KEY]}
ENABLE_CORS=${CONFIG_VALUES[ENABLE_CORS]:-false}
CORS_ORIGINS=${CONFIG_VALUES[CORS_ORIGINS]:-*}
ENABLE_RATE_LIMIT=${CONFIG_VALUES[ENABLE_RATE_LIMIT]:-false}
RATE_LIMIT_REQUESTS=${CONFIG_VALUES[RATE_LIMIT_REQUESTS]:-100}
RATE_LIMIT_WINDOW=${CONFIG_VALUES[RATE_LIMIT_WINDOW]:-60}

EOF

        # SSL Configuration
        if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]]; then
            cat << EOF
#------------------------------------------------------------------------------
# SSL/TLS CONFIGURATION
#------------------------------------------------------------------------------
SSL_ENABLED=true
SSL_TYPE=${CONFIG_VALUES[SSL_TYPE]}
SSL_CERT_PATH=${CONFIG_VALUES[SSL_CERT_PATH]:-}
SSL_KEY_PATH=${CONFIG_VALUES[SSL_KEY_PATH]:-}
SSL_EMAIL=${CONFIG_VALUES[SSL_EMAIL]:-}
SSL_DOMAIN=${CONFIG_VALUES[SSL_DOMAIN]:-}
FORCE_HTTPS=${CONFIG_VALUES[FORCE_HTTPS]:-true}

EOF
        fi

        # Logging
        cat << EOF
#------------------------------------------------------------------------------
# LOGGING CONFIGURATION
#------------------------------------------------------------------------------
LOG_LEVEL=${CONFIG_VALUES[LOG_LEVEL]:-info}
LOG_FORMAT=${CONFIG_VALUES[LOG_FORMAT]:-json}
ENABLE_LOG_ROTATION=${CONFIG_VALUES[ENABLE_LOG_ROTATION]:-true}
LOG_MAX_SIZE=${CONFIG_VALUES[LOG_MAX_SIZE]:-100m}
LOG_MAX_FILES=${CONFIG_VALUES[LOG_MAX_FILES]:-10}

EOF

        # Backup Configuration
        if [[ "${CONFIG_VALUES[ENABLE_BACKUPS]}" == "true" ]]; then
            cat << EOF
#------------------------------------------------------------------------------
# BACKUP CONFIGURATION
#------------------------------------------------------------------------------
BACKUP_ENABLED=true
BACKUP_PATH=${CONFIG_VALUES[BACKUP_PATH]}
BACKUP_SCHEDULE=${CONFIG_VALUES[BACKUP_SCHEDULE]:-}
BACKUP_RETENTION_DAYS=${CONFIG_VALUES[BACKUP_RETENTION_DAYS]:-7}
BACKUP_ENCRYPTION=${CONFIG_VALUES[BACKUP_ENCRYPTION]:-false}
BACKUP_ENCRYPTION_KEY=${CONFIG_VALUES[BACKUP_ENCRYPTION_KEY]:-}

EOF
        fi

        # Docker Configuration
        cat << EOF
#------------------------------------------------------------------------------
# DOCKER CONFIGURATION
#------------------------------------------------------------------------------
COMPOSE_PROJECT_NAME=${CONFIG_VALUES[COMPOSE_PROJECT_NAME]:-aiplatform}
DOCKER_NETWORK_NAME=${CONFIG_VALUES[DOCKER_NETWORK_NAME]:-aiplatform_network}
DEFAULT_RESTART_POLICY=${CONFIG_VALUES[DEFAULT_RESTART_POLICY]:-unless-stopped}

EOF

        # Custom variables
        if [[ -n "${CONFIG_VALUES[CUSTOM_ENV_VARS]:-}" ]]; then
            cat << EOF
#------------------------------------------------------------------------------
# CUSTOM ENVIRONMENT VARIABLES
#------------------------------------------------------------------------------
${CONFIG_VALUES[CUSTOM_ENV_VARS]}

EOF
        fi

    } > "$env_file"

    # Set restrictive permissions on .env file
    chmod 600 "$env_file"

    log_success ".env file generated: $env_file"
}

# Generate docker-compose.yml
generate_docker_compose() {
    log_info "Generating docker-compose.yml..."

    local compose_file="${PROJECT_ROOT}/docker-compose.yml"

    # Backup existing compose file
    if [[ -f "$compose_file" ]]; then
        local backup_file="${compose_file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$compose_file" "$backup_file"
        log_info "Backed up existing docker-compose.yml to: $backup_file"
    fi

    # Create docker-compose.yml
    {
        cat << EOF
version: '${CONFIG_VALUES[COMPOSE_FILE_VERSION]:-3.8}'

################################################################################
# AI PLATFORM DOCKER COMPOSE
# Generated by install.sh
# Date: $(date)
################################################################################

services:

EOF

        # Ollama Service
        if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
            cat << EOF
  ollama:
    image: ollama/ollama:\${OLLAMA_VERSION:-latest}
    container_name: \${COMPOSE_PROJECT_NAME:-aiplatform}_ollama
    restart: \${DEFAULT_RESTART_POLICY:-unless-stopped}
    ports:
      - "\${OLLAMA_PORT:-11434}:11434"
    environment:
      - OLLAMA_NUM_PARALLEL=\${OLLAMA_NUM_PARALLEL:-1}
      - OLLAMA_MAX_LOADED_MODELS=\${OLLAMA_MAX_LOADED_MODELS:-1}
      - OLLAMA_KEEP_ALIVE=\${OLLAMA_KEEP_ALIVE:-5m}
    volumes:
      - ollama_data:/root/.ollama
    networks:
      - aiplatform_network
EOF

            # Add GPU support if configured
            if [[ "${CONFIG_VALUES[ENABLE_GPU]}" == "true" ]]; then
                cat << EOF
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
EOF
            fi

            echo ""
        fi

        # Open WebUI Service
        if [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]]; then
            cat << EOF
  webui:
    image: ghcr.io/open-webui/open-webui:\${WEBUI_VERSION:-main}
    container_name: \${COMPOSE_PROJECT_NAME:-aiplatform}_webui
    restart: \${DEFAULT_RESTART_POLICY:-unless-stopped}
    ports:
      - "\${WEBUI_PORT:-3000}:8080"
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - WEBUI_SECRET_KEY=\${WEBUI_SECRET_KEY}
      - WEBUI_NAME=\${WEBUI_NAME:-AI Platform}
    volumes:
      - webui_data:/app/backend/data
    networks:
      - aiplatform_network
    depends_on:
      - ollama
    extra_hosts:
      - "host.docker.internal:host-gateway"

EOF
        fi

        # PostgreSQL Service
        if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
            cat << EOF
  postgres:
    image: postgres:\${POSTGRES_VERSION:-15-alpine}
    container_name: \${COMPOSE_PROJECT_NAME:-aiplatform}_postgres
    restart: \${DEFAULT_RESTART_POLICY:-unless-stopped}
    ports:
      - "\${POSTGRES_PORT:-5432}:5432"
    environment:
      - POSTGRES_DB=\${POSTGRES_DB:-aiplatform}
      - POSTGRES_USER=\${POSTGRES_USER:-postgres}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_INITDB_ARGS=--encoding=UTF8 --lc-collate=C --lc-ctype=C
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - aiplatform_network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER:-postgres}"]
      interval: 10s
      timeout: 5s
      retries: 5

EOF
        fi

        # Add remaining services (Redis, n8n, monitoring, etc.)
        # ... (similar blocks for each enabled service)

        # Networks
        cat << EOF
networks:
  aiplatform_network:
    driver: \${DOCKER_NETWORK_DRIVER:-bridge}
EOF

        if [[ "${CONFIG_VALUES[DOCKER_NETWORK_DRIVER]}" == "bridge" ]] && [[ -n "${CONFIG_VALUES[DOCKER_NETWORK_SUBNET]:-}" ]]; then
            cat << EOF
    ipam:
      config:
        - subnet: \${DOCKER_NETWORK_SUBNET}
          gateway: \${DOCKER_NETWORK_GATEWAY}
EOF
        fi

        # Volumes
        cat << EOF

volumes:
EOF

        [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]] && echo "  ollama_data:"
        [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]] && echo "  webui_data:"
        [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]] && echo "  postgres_data:"
        [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]] && echo "  redis_data:"
        [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]] && echo "  n8n_data:"
        [[ "${CONFIG_VALUES[INSTALL_PROMETHEUS]}" == "true" ]] && echo "  prometheus_data:"
        [[ "${CONFIG_VALUES[INSTALL_GRAFANA]}" == "true" ]] && echo "  grafana_data:"

    } > "$compose_file"

    log_success "docker-compose.yml generated: $compose_file"
}

# Save configuration to file
save_configuration() {
    log_info "Saving configuration..."

    local config_save_file="${CONFIG_DIR}/installation-config.json"

    # Convert associative array to JSON
    {
        echo "{"
        local first=true
        for key in "${!CONFIG_VALUES[@]}"; do
            [[ "$first" == true ]] && first=false || echo ","
            # Escape quotes in values
            local value="${CONFIG_VALUES[$key]//\"/\\\"}"
            echo "  \"$key\": \"$value\""
        done
        echo "}"
    } > "$config_save_file"

    chmod 600 "$config_save_file"
    log_success "Configuration saved to: $config_save_file"

    # Also save a human-readable version
    local config_readable="${CONFIG_DIR}/installation-config.txt"
    {
        echo "AI Platform Installation Configuration"
        echo "========================================"
        echo "Generated: $(date)"
        echo ""
        for key in "${!CONFIG_VALUES[@]}"; do
            if [[ "$key" =~ PASSWORD|SECRET|KEY|TOKEN ]]; then
                echo "$key=********"
            else
                echo "$key=${CONFIG_VALUES[$key]}"
            fi
        done
    } > "$config_readable"

    log_success "Readable configuration saved to: $config_readable"
}
################################################################################
# INSTALLATION EXECUTION FUNCTIONS
################################################################################

# Execute system setup
execute_system_setup() {
    log_info "Executing system setup..."

    # Install required system packages
    if [[ "${CONFIG_VALUES[INSTALL_TYPE]}" == "full" ]] || [[ "${CONFIG_VALUES[INSTALL_TYPE]}" == "production" ]]; then
        log_info "Installing system dependencies..."

        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y \
                curl \
                wget \
                git \
                jq \
                openssl \
                ca-certificates \
                gnupg \
                lsb-release
        elif command -v yum &> /dev/null; then
            sudo yum install -y \
                curl \
                wget \
                git \
                jq \
                openssl \
                ca-certificates
        fi
    fi

    # Install Docker if needed
    if ! command -v docker &> /dev/null; then
        log_warn "Docker not found. Installing Docker..."

        if prompt_yes_no "Install Docker now?" "y"; then
            curl -fsSL https://get.docker.com -o get-docker.sh
            sudo sh get-docker.sh
            sudo usermod -aG docker " $ USER"
            rm get-docker.sh
            log_success "Docker installed successfully"
            log_warn "You may need to log out and back in for group changes to take effect"
        else
            log_error "Docker is required. Please install Docker manually and re-run this script"
            exit 1
        fi
    fi

    # Install Docker Compose if needed
    if ! command -v docker-compose &> /dev/null; then
        log_warn "Docker Compose not found. Installing Docker Compose..."

        if prompt_yes_no "Install Docker Compose now?" "y"; then
            sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose- $ (uname -s)- $ (uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
            log_success "Docker Compose installed successfully"
        else
            log_error "Docker Compose is required. Please install it manually and re-run this script"
            exit 1
        fi
    fi

    # Verify Docker is running
    if ! sudo docker ps &> /dev/null; then
        log_error "Docker is not running. Please start Docker and try again"
        exit 1
    fi

    log_success "System setup completed"
}

# Create directory structure
create_directory_structure() {
    log_info "Creating directory structure..."

    local dirs=(
        " $ PROJECT_ROOT"
        " $ CONFIG_DIR"
        " $ LOG_DIR"
        " $ BACKUP_DIR"
        " $ SCRIPT_DIR/templates"
        " $ SCRIPT_DIR/scripts"
    )

    # Add custom storage paths if configured
    if [[ " $ {CONFIG_VALUES[STORAGE_TYPE]}" == "custom-paths" ]]; then
        dirs+=("${CONFIG_VALUES[DATA_ROOT]}")
        [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]] && dirs+=("${CONFIG_VALUES[OLLAMA_MODELS_PATH]}")
        [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]] && dirs+=("${CONFIG_VALUES[POSTGRES_DATA_PATH]}")
        [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]] && dirs+=("${CONFIG_VALUES[REDIS_DATA_PATH]}")
        [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]] && dirs+=("${CONFIG_VALUES[N8N_DATA_PATH]}")
        [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]] && dirs+=("${CONFIG_VALUES[WEBUI_DATA_PATH]}")
    fi

    # Add SSL directory if SSL is enabled
    [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]] && dirs+=("${PROJECT_ROOT}/ssl")

    # Add backup path if backups are enabled
    [[ "${CONFIG_VALUES[ENABLE_BACKUPS]}" == "true" ]] && dirs+=("${CONFIG_VALUES[BACKUP_PATH]}")

    # Add monitoring config directories if enabled
    [[ "${CONFIG_VALUES[INSTALL_PROMETHEUS]}" == "true" ]] && dirs+=("${PROJECT_ROOT}/prometheus")
    [[ "${CONFIG_VALUES[INSTALL_GRAFANA]}" == "true" ]] && dirs+=("${PROJECT_ROOT}/grafana")

    # Add nginx config directory if enabled
    [[ "${CONFIG_VALUES[INSTALL_NGINX]}" == "true" ]] && dirs+=("${PROJECT_ROOT}/nginx")

    for dir in "${dirs[@]}"; do
        if [[ ! -d " $ dir" ]]; then
            mkdir -p " $ dir"
            log_success "Created: $dir"
        else
            log_info "Already exists:  $ dir"
        fi
    done

    # Set appropriate permissions
    chmod 755 " $ PROJECT_ROOT"
    chmod 700 " $ CONFIG_DIR"
    chmod 755 " $ LOG_DIR"
    [[ -d " $ BACKUP_DIR" ]] && chmod 700 " $ BACKUP_DIR"

    log_success "Directory structure created"
}

# Generate all configuration files
generate_all_configs() {
    log_info "Generating configuration files..."

    # Generate .env file
    generate_env_file

    # Generate docker-compose.yml
    generate_docker_compose

    # Generate Nginx config if enabled
    if [[ "${CONFIG_VALUES[INSTALL_NGINX]}" == "true" ]]; then
        generate_nginx_config
    fi

    # Generate Prometheus config if enabled
    if [[ "${CONFIG_VALUES[INSTALL_PROMETHEUS]}" == "true" ]]; then
        generate_prometheus_config
    fi

    # Generate backup script if enabled
    if [[ "${CONFIG_VALUES[ENABLE_BACKUPS]}" == "true" ]]; then
        generate_backup_script
    fi

    # Generate helper scripts
    generate_helper_scripts

    # Save configuration
    save_configuration

    log_success "All configuration files generated"
}

# Generate Nginx configuration
generate_nginx_config() {
    log_info "Generating Nginx configuration..."

    local nginx_conf="${PROJECT_ROOT}/nginx/nginx.conf"

    cat > "$nginx_conf" << 'EOF'
user nginx;
worker_processes ${NGINX_WORKER_PROCESSES:-auto};
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections ${NGINX_WORKER_CONNECTIONS:-1024};
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr -  $ remote_user [ $ time_local] " $ request" '
                    ' $ status  $ body_bytes_sent " $ http_referer" '
                    '" $ http_user_agent" " $ http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout ${NGINX_KEEPALIVE_TIMEOUT:-65};
    types_hash_max_size 2048;
    client_max_body_size ${NGINX_CLIENT_MAX_BODY_SIZE:-100M};

    gzip ${NGINX_GZIP:-on};
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript application/json application/javascript application/xml+rss application/rss+xml font/truetype font/opentype application/vnd.ms-fontobject image/svg+xml;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    include /etc/nginx/conf.d/*.conf;
}
EOF

    # Generate service-specific configs
    local nginx_conf_d="${PROJECT_ROOT}/nginx/conf.d"
    mkdir -p " $ nginx_conf_d"

    # Default server config
    cat > " $ {nginx_conf_d}/default.conf" << EOF
server {
    listen ${CONFIG_VALUES[NGINX_HTTP_PORT]:-80};
    server_name _;

EOF

    if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" && "${CONFIG_VALUES[FORCE_HTTPS]}" == "true" ]]; then
        cat >> "${nginx_conf_d}/default.conf" << EOF
    return 301 https://\ $ host\ $ request_uri;
}

server {
    listen ${CONFIG_VALUES[NGINX_HTTPS_PORT]:-443} ssl http2;
    server_name _;

    ssl_certificate ${CONFIG_VALUES[SSL_CERT_PATH]};
    ssl_certificate_key ${CONFIG_VALUES[SSL_KEY_PATH]};
    ssl_protocols ${CONFIG_VALUES[SSL_PROTOCOLS]:-TLSv1.2 TLSv1.3};
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

EOF

        if [[ "${CONFIG_VALUES[HSTS_ENABLED]}" == "true" ]]; then
            echo "    add_header Strict-Transport-Security \"max-age=${CONFIG_VALUES[HSTS_MAX_AGE]:-31536000}\" always;" >> "${nginx_conf_d}/default.conf"
        fi
    fi

    # Add upstream and location blocks for each service
    if [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]]; then
        cat >> "${nginx_conf_d}/default.conf" << EOF

    location ${CONFIG_VALUES[WEBUI_PATH]:-/} {
        proxy_pass http://webui:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \ $ http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \ $ host;
        proxy_set_header X-Real-IP \ $ remote_addr;
        proxy_set_header X-Forwarded-For \ $ proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \ $ scheme;
        proxy_cache_bypass \ $ http_upgrade;
    }
EOF
    fi

    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        cat >> "${nginx_conf_d}/default.conf" << EOF

    location ${CONFIG_VALUES[N8N_PATH]:-/n8n} {
        proxy_pass http://n8n:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \ $ http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \ $ host;
        proxy_cache_bypass \ $ http_upgrade;
    }
EOF
    fi

    # Close server block
    echo "}" >> " $ {nginx_conf_d}/default.conf"

    log_success "Nginx configuration generated"
}

# Generate Prometheus configuration
generate_prometheus_config() {
    log_info "Generating Prometheus configuration..."

    local prom_config="${PROJECT_ROOT}/prometheus/prometheus.yml"

    cat > " $ prom_config" << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    monitor: 'ai-platform'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

EOF

    # Add scrape configs for enabled services
    if [[ " $ {CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        cat >> " $ prom_config" << EOF
  - job_name: 'ollama'
    static_configs:
      - targets: ['ollama: $ {CONFIG_VALUES[OLLAMA_PORT]:-11434}']

EOF
    fi

    log_success "Prometheus configuration generated"
}

# Generate backup script
generate_backup_script() {
    log_info "Generating backup script..."

    local backup_script="${SCRIPT_DIR}/scripts/backup.sh"

    cat > " $ backup_script" << 'EOF'
#!/bin/bash
################################################################################
# AI Platform Backup Script
# Generated by install.sh
################################################################################

set -euo pipefail

BACKUP_DIR=" $ {BACKUP_PATH:-/backup/aiplatform}"
TIMESTAMP= $ (date +%Y%m%d_%H%M%S)
BACKUP_NAME="aiplatform_backup_ $ {TIMESTAMP}"
TEMP_DIR="/tmp/${BACKUP_NAME}"

# Create backup directory
mkdir -p " $ TEMP_DIR"

# Backup Docker volumes
echo "Backing up Docker volumes..."
docker run --rm \
    -v aiplatform_ollama_data:/data/ollama \
    -v " $ {TEMP_DIR}:/backup" \
    alpine tar czf "/backup/ollama_data.tar.gz" -C /data/ollama .

# Backup configuration files
echo "Backing up configuration..."
tar czf "${TEMP_DIR}/config.tar.gz" \
    -C "${PROJECT_ROOT}" \
    .env docker-compose.yml nginx/ prometheus/ 2>/dev/null || true

# Backup databases
if [[ "${INSTALL_POSTGRES}" == "true" ]]; then
    echo "Backing up PostgreSQL..."
    docker exec aiplatform_postgres pg_dumpall -U postgres | gzip > "${TEMP_DIR}/postgres_dump.sql.gz"
fi

# Create final backup archive
echo "Creating backup archive..."
tar czf "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" -C /tmp "${BACKUP_NAME}"

# Cleanup
rm -rf " $ TEMP_DIR"

# Apply retention policy
find " $ BACKUP_DIR" -name "aiplatform_backup_*.tar.gz" -mtime +${BACKUP_RETENTION_DAYS:-7} -delete

echo "Backup completed: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
EOF

    chmod +x "$backup_script"
    log_success "Backup script generated:  $ backup_script"

    # Setup cron job if schedule is defined
 # Setup cron job if schedule is defined
    if [[ -n "${CONFIG_VALUES[BACKUP_SCHEDULE]:-}" ]]; then
        log_info "Setting up backup cron job..."
        
        local cron_entry="${CONFIG_VALUES[BACKUP_SCHEDULE]} ${backup_script} >> ${LOG_DIR}/backup.log 2>&1"
        
        # Check if cron entry already exists
        if ! crontab -l 2>/dev/null | grep -q "$backup_script"; then
            (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
            log_success "Backup cron job installed: ${CONFIG_VALUES[BACKUP_SCHEDULE]}"
        else
            log_info "Backup cron job already exists"
        fi
    fi
}

# Generate helper scripts
generate_helper_scripts() {
    log_info "Generating helper scripts..."
    
    # Generate start script
    cat > "${SCRIPT_DIR}/start.sh" << 'EOF'
#!/bin/bash
################################################################################
# AI Platform Start Script
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "Starting AI Platform..."
docker-compose up -d

echo ""
echo "Waiting for services to be ready..."
sleep 5

echo ""
echo "Service Status:"
docker-compose ps

echo ""
echo "Access points:"
grep -E "WEBUI_PORT|N8N_PORT|GRAFANA_PORT" .env | while IFS= read -r line; do
    echo "  $line"
done

echo ""
echo "To view logs: docker-compose logs -f"
echo "To stop: ./scripts/stop.sh"
EOF
    
    chmod +x "${SCRIPT_DIR}/start.sh"
    
    # Generate stop script
    cat > "${SCRIPT_DIR}/stop.sh" << 'EOF'
#!/bin/bash
################################################################################
# AI Platform Stop Script
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "Stopping AI Platform..."
docker-compose down

echo "All services stopped."
EOF
    
    chmod +x "${SCRIPT_DIR}/stop.sh"
    
    # Generate restart script
    cat > "${SCRIPT_DIR}/restart.sh" << 'EOF'
#!/bin/bash
################################################################################
# AI Platform Restart Script
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Restarting AI Platform..."
"$SCRIPT_DIR/stop.sh"
sleep 2
"$SCRIPT_DIR/start.sh"
EOF
    
    chmod +x "${SCRIPT_DIR}/restart.sh"
    
    # Generate status script
    cat > "${SCRIPT_DIR}/status.sh" << 'EOF'
#!/bin/bash
################################################################################
# AI Platform Status Script
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "AI Platform Status"
echo "=================="
echo ""

echo "Docker Containers:"
docker-compose ps

echo ""
echo "Resource Usage:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" $(docker-compose ps -q)

echo ""
echo "Disk Usage:"
docker system df

echo ""
echo "Network Status:"
docker network inspect aiplatform_network --format '{{range .Containers}}{{.Name}}: {{.IPv4Address}}{{"\n"}}{{end}}' 2>/dev/null || echo "Network not found"

echo ""
echo "Recent Logs:"
docker-compose logs --tail=10
EOF
    
    chmod +x "${SCRIPT_DIR}/status.sh"
    
    # Generate logs script
    cat > "${SCRIPT_DIR}/logs.sh" << 'EOF'
#!/bin/bash
################################################################################
# AI Platform Logs Script
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

SERVICE="${1:-}"

if [[ -z "$SERVICE" ]]; then
    echo "Following all service logs (Ctrl+C to exit)..."
    docker-compose logs -f
else
    echo "Following logs for: $SERVICE"
    docker-compose logs -f "$SERVICE"
fi
EOF
    
    chmod +x "${SCRIPT_DIR}/logs.sh"
    
    # Generate update script
    cat > "${SCRIPT_DIR}/update.sh" << 'EOF'
#!/bin/bash
################################################################################
# AI Platform Update Script
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "Updating AI Platform..."
echo ""

# Pull latest images
echo "Pulling latest Docker images..."
docker-compose pull

# Recreate containers with new images
echo ""
echo "Recreating containers..."
docker-compose up -d --force-recreate

# Cleanup old images
echo ""
read -p "Remove old Docker images? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker image prune -f
fi

echo ""
echo "Update complete!"
echo "Check status with: ./scripts/status.sh"
EOF
    
    chmod +x "${SCRIPT_DIR}/update.sh"
    
    # Generate cleanup script
    cat > "${SCRIPT_DIR}/cleanup.sh" << 'EOF'
#!/bin/bash
################################################################################
# AI Platform Cleanup Script
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "AI Platform Cleanup Utility"
echo "==========================="
echo ""
echo "This will help clean up Docker resources."
echo ""

# Show current usage
echo "Current Docker disk usage:"
docker system df
echo ""

# Cleanup options
PS3="Select cleanup option: "
options=(
    "Remove stopped containers"
    "Remove unused images"
    "Remove unused volumes"
    "Remove unused networks"
    "Full cleanup (all unused resources)"
    "Cancel"
)

select opt in "${options[@]}"; do
    case $opt in
        "Remove stopped containers")
            docker container prune -f
            break
            ;;
        "Remove unused images")
            docker image prune -a -f
            break
            ;;
        "Remove unused volumes")
            echo "WARNING: This will remove ALL unused volumes!"
            read -p "Are you sure? (yes/no) " -r
            if [[ $REPLY == "yes" ]]; then
                docker volume prune -f
            fi
            break
            ;;
        "Remove unused networks")
            docker network prune -f
            break
            ;;
        "Full cleanup (all unused resources)")
            echo "WARNING: This will remove all stopped containers, unused images, volumes, and networks!"
            read -p "Are you sure? (yes/no) " -r
            if [[ $REPLY == "yes" ]]; then
                docker system prune -a --volumes -f
            fi
            break
            ;;
        "Cancel")
            echo "Cleanup cancelled"
            exit 0
            ;;
        *)
            echo "Invalid option"
            ;;
    esac
done

echo ""
echo "Updated Docker disk usage:"
docker system df
EOF
    
    chmod +x "${SCRIPT_DIR}/cleanup.sh"
    
    # Generate health check script
    cat > "${SCRIPT_DIR}/health-check.sh" << 'EOF'
#!/bin/bash
################################################################################
# AI Platform Health Check Script
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Load environment
source .env

echo "AI Platform Health Check"
echo "========================"
echo ""

FAILED=0

# Check Docker
echo -n "Docker daemon: "
if docker info &>/dev/null; then
    echo "✓ Running"
else
    echo "✗ Not running"
    ((FAILED++))
fi

# Check containers
echo ""
echo "Container Health:"
docker-compose ps -q | while read container_id; do
    container_name=$(docker inspect --format='{{.Name}}' "$container_id" | sed 's/\///')
    container_status=$(docker inspect --format='{{.State.Status}}' "$container_id")
    container_health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no healthcheck{{end}}' "$container_id")
    
    echo -n "  $container_name: "
    if [[ "$container_status" == "running" ]]; then
        if [[ "$container_health" == "healthy" ]] || [[ "$container_health" == "no healthcheck" ]]; then
            echo "✓ $container_status ($container_health)"
        else
            echo "⚠ $container_status ($container_health)"
            ((FAILED++))
        fi
    else
        echo "✗ $container_status"
        ((FAILED++))
    fi
done

# Check disk space
echo ""
echo -n "Disk space: "
DISK_USAGE=$(df -h "$PROJECT_ROOT" | awk 'NR==2 {print $5}' | sed 's/%//')
if [[ $DISK_USAGE -lt 90 ]]; then
    echo "✓ ${DISK_USAGE}% used"
else
    echo "⚠ ${DISK_USAGE}% used (high usage)"
    ((FAILED++))
fi

# Check ports
echo ""
echo "Port Availability:"
check_port() {
    local port=$1
    local name=$2
    echo -n "  $name ($port): "
    if nc -z localhost "$port" 2>/dev/null; then
        echo "✓ Responding"
    else
        echo "✗ Not responding"
        ((FAILED++))
    fi
}

[[ -n "${WEBUI_PORT:-}" ]] && check_port "$WEBUI_PORT" "WebUI"
[[ -n "${OLLAMA_PORT:-}" ]] && check_port "$OLLAMA_PORT" "Ollama"
[[ -n "${N8N_PORT:-}" ]] && check_port "$N8N_PORT" "n8n"
[[ -n "${POSTGRES_PORT:-}" ]] && check_port "$POSTGRES_PORT" "PostgreSQL"
[[ -n "${REDIS_PORT:-}" ]] && check_port "$REDIS_PORT" "Redis"
[[ -n "${GRAFANA_PORT:-}" ]] && check_port "$GRAFANA_PORT" "Grafana"

# Summary
echo ""
echo "========================"
if [[ $FAILED -eq 0 ]]; then
    echo "✓ All checks passed"
    exit 0
else
    echo "✗ $FAILED check(s) failed"
    exit 1
fi
EOF
    
    chmod +x "${SCRIPT_DIR}/health-check.sh"
    
    log_success "Helper scripts generated in ${SCRIPT_DIR}/"
}

# Deploy services
deploy_services() {
    log_info "Deploying services..."
    
    cd "$PROJECT_ROOT"
    
    # Pull images first
    log_info "Pulling Docker images..."
    if ! docker-compose pull; then
        log_error "Failed to pull Docker images"
        return 1
    fi
    
    # Start services
    log_info "Starting services..."
    if ! docker-compose up -d; then
        log_error "Failed to start services"
        return 1
    fi
    
    # Wait for services to be ready
    log_info "Waiting for services to be ready..."
    sleep 10
    
    # Check service health
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if docker-compose ps | grep -q "Up"; then
            log_success "Services are running"
            break
        fi
        
        ((attempt++))
        sleep 2
        
        if [[ $attempt -eq $max_attempts ]]; then
            log_error "Services failed to start properly"
            docker-compose logs
            return 1
        fi
    done
    
    log_success "Services deployed successfully"
    return 0
}

# Post-installation tasks
post_installation() {
    log_info "Running post-installation tasks..."
    
    # Download Ollama models if requested
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]] && [[ "${CONFIG_VALUES[DOWNLOAD_MODELS]}" == "true" ]]; then
        log_info "Downloading Ollama models..."
        
        IFS=',' read -ra MODELS <<< "${CONFIG_VALUES[OLLAMA_MODELS]}"
        for model in "${MODELS[@]}"; do
            model=$(echo "$model" | xargs) # trim whitespace
            log_info "Downloading model: $model"
            docker exec aiplatform_ollama ollama pull "$model" || log_warn "Failed to download $model"
        done
    fi
    
    # Setup SSL certificates if using Let's Encrypt
    if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]] && [[ "${CONFIG_VALUES[SSL_TYPE]}" == "letsencrypt" ]]; then
        log_info "Setting up Let's Encrypt certificates..."
        
        docker run --rm \
            -v "${PROJECT_ROOT}/ssl:/etc/letsencrypt" \
            -p 80:80 \
            certbot/certbot certonly \
            --standalone \
            --non-interactive \
            --agree-tos \
            --email "${CONFIG_VALUES[SSL_EMAIL]}" \
            -d "${CONFIG_VALUES[SSL_DOMAIN]}" \
            ${CONFIG_VALUES[LETSENCRYPT_STAGING]:+--staging}
    fi
    
    # Initialize databases if needed
    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
        log_info "Initializing PostgreSQL databases..."
        sleep 5 # Wait for PostgreSQL to be fully ready
        
        # Create databases for services
        if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
            docker exec aiplatform_postgres psql -U postgres -c "CREATE DATABASE n8n;" 2>/dev/null || true
        fi
    fi
    
    log_success "Post-installation tasks completed"
}

# Display installation summary
display_summary() {
    clear
    
    cat << EOF

${GREEN}╔════════════════════════════════════════════════════════════════════╗
║                                                                    ║
║            AI PLATFORM INSTALLATION COMPLETED!                     ║
║                                                                    ║
╚════════════════════════════════════════════════════════════════════╝${NC}

${BOLD}Installation Summary:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

${BOLD}Project Location:${NC}
  ${PROJECT_ROOT}

${BOLD}Installed Services:${NC}
EOF

    [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]] && echo "  ✓ Ollama (Port: ${CONFIG_VALUES[OLLAMA_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]] && echo "  ✓ Open WebUI (Port: ${CONFIG_VALUES[WEBUI_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_NGINX]}" == "true" ]] && echo "  ✓ Nginx Reverse Proxy"
    [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]] && echo "  ✓ PostgreSQL (Port: ${CONFIG_VALUES[POSTGRES_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]] && echo "  ✓ Redis (Port: ${CONFIG_VALUES[REDIS_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]] && echo "  ✓ n8n (Port: ${CONFIG_VALUES[N8N_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_PROMETHEUS]}" == "true" ]] && echo "  ✓ Prometheus (Port: ${CONFIG_VALUES[PROMETHEUS_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_GRAFANA]}" == "true" ]] && echo "  ✓ Grafana (Port: ${CONFIG_VALUES[GRAFANA_PORT]})"

    cat << EOF

${BOLD}Access Points:${NC}
EOF

    local protocol="http"
    [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]] && protocol="https"
    
    [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]] && echo "  • WebUI: ${protocol}://localhost:${CONFIG_VALUES[WEBUI_PORT]}"
    [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]] && echo "  • n8n: ${protocol}://localhost:${CONFIG_VALUES[N8N_PORT]}"
    [[ "${CONFIG_VALUES[INSTALL_GRAFANA]}" == "true" ]] && echo "  • Grafana: ${protocol}://localhost:${CONFIG_VALUES[GRAFANA_PORT]}"

    cat << EOF

${BOLD}Useful Commands:${NC}
  Start services:     ${PROJECT_ROOT}/scripts/start.sh
  Stop services:      ${PROJECT_ROOT}/scripts/stop.sh
  View status:        ${PROJECT_ROOT}/scripts/status.sh
  View logs:          ${PROJECT_ROOT}/scripts/logs.sh [service]
  Health check:       ${PROJECT_ROOT}/scripts/health-check.sh
  Update platform:    ${PROJECT_ROOT}/scripts/update.sh

${BOLD}Configuration Files:${NC}
  Environment:        ${PROJECT_ROOT}/.env
  Docker Compose:     ${PROJECT_ROOT}/docker-compose.yml
  Saved Config:       ${CONFIG_DIR}/installation-config.json

${BOLD}Log Files:${NC}
  Installation Log:   ${LOG_DIR}/install.log
  Service Logs:       docker-compose logs -f

EOF

    if [[ "${CONFIG_VALUES[ENABLE_BACKUPS]}" == "true" ]]; then
        cat << EOF
${BOLD}Backups:${NC}
  Location:           ${CONFIG_VALUES[BACKUP_PATH]}
  Schedule:           ${CONFIG_VALUES[BACKUP_SCHEDULE]}
  Retention:          ${CONFIG_VALUES[BACKUP_RETENTION_DAYS]} days

EOF
    fi

    if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]]; then
        cat << EOF
${BOLD}SSL Configuration:${NC}
  Type:               ${CONFIG_VALUES[SSL_TYPE]}
  Certificate:        ${CONFIG_VALUES[SSL_CERT_PATH]:-N/A}

EOF
    fi

    cat << EOF
${BOLD}Next Steps:${NC}
  1. Verify services are running: ${PROJECT_ROOT}/scripts/status.sh
  2. Check service health: ${PROJECT_ROOT}/scripts/health-check.sh
  3. Access the WebUI and complete initial setup
  4. Review logs if any issues: docker-compose logs

${BOLD}Documentation:${NC}
  README:             ${PROJECT_ROOT}/README.md
  Configuration:      ${CONFIG_DIR}/installation-config.txt

${YELLOW}Important Security Notes:${NC}
  • Change default passwords immediately
  • Review firewall rules
  • Enable SSL/TLS for production use
  • Keep sensitive credentials secure
  • Regularly update services and review logs

${GREEN}Thank you for using AI Platform!${NC}

For support and updates, visit: https://github.com/yourusername/ai-platform

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    # Display banner
    display_banner
    
    # Pre-flight checks
    log_info "Running pre-flight checks..."
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root"
        exit 1
    fi
    
    # Check if Docker is available (can be installed later)
    if ! command -v docker &> /dev/null; then
        log_warn "Docker not found - will offer to install during setup"
    fi
    
    # Create initial directory structure
    mkdir -p "$LOG_DIR" "$CONFIG_DIR"
    
    # Start logging
    exec > >(tee -a "$LOG_FILE")
    exec 2>&1
    
    log_info "Installation started at $(date)"
    log_info "Log file: $LOG_FILE"
    
    # Run configuration wizard
    log_info "Starting configuration wizard..."
    
    collect_installation_type
    collect_project_info
    collect_stack_selection
    collect_service_configs
    collect_storage_config
    collect_database_configs
    collect_proxy_config
    collect_auth_config
    collect_monitoring_config
    collect_network_config
    collect_resource_limits
    collect_ssl_config
    collect_backup_config
    collect_advanced_options
    
    # Confirmation
    echo ""
    log_info "Configuration complete. Review your selections above."
    echo ""
    
    if ! prompt_yes_no "Proceed with installation?" "y"; then
        log_warn "Installation cancelled by user"
        exit 0
    fi
    
    # Execute installation
    log_info "Beginning installation..."
    
    execute_system_setup
    create_directory_structure
    generate_all_configs
    deploy_services
    post_installation
    
    # Display summary
    display_summary
    
    log_success "Installation completed successfully at $(date)"
}

# Trap errors
trap 'log_error "Installation failed at line $LINENO. Check log file: $LOG_FILE"' ERR

# Run main function
main "$@"
