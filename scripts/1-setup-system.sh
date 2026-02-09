#!/bin/bash
################################################################################
# AI Platform System Setup Script
# Version: 1.0.0
# Description: Interactive installation wizard for AI platform stack
################################################################################

set -euo pipefail
IFS=$'\n\t'

################################################################################
# CONSTANTS AND GLOBALS
################################################################################

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly CONFIG_DIR="${PROJECT_ROOT}/config"
readonly LOG_DIR="${PROJECT_ROOT}/logs"
readonly BACKUP_DIR="${PROJECT_ROOT}/backups"
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)
readonly LOG_FILE="${LOG_DIR}/setup_${TIMESTAMP}.log"

# Version information
readonly VERSION="1.0.0"
readonly MIN_DOCKER_VERSION="20.10.0"
readonly MIN_COMPOSE_VERSION="2.0.0"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# Configuration storage
declare -A CONFIG_VALUES

################################################################################
# LOGGING FUNCTIONS
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

log_step() {
    echo -e "\n${CYAN}${BOLD}=== $* ===${NC}\n" | tee -a "$LOG_FILE"
}

################################################################################
# UTILITY FUNCTIONS
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
    
    read -rp "$prompt" response
    response=${response:-$default}
    
    [[ "$response" =~ ^[Yy]$ ]]
}

prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local response
    
    read -rp "$prompt [$default]: " response
    echo "${response:-$default}"
}

validate_email() {
    local email="$1"
    [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

validate_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

validate_domain() {
    local domain="$1"
    [[ "$domain" =~ ^([a-zA-Z0-9]([-a-zA-Z0-9]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

generate_random_password() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
}

version_gt() {
    test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

################################################################################
# SYSTEM CHECKS
################################################################################

check_system_requirements() {
    log_step "Checking System Requirements"
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        log_warning "Running as root. This is not recommended for production."
        if ! prompt_yes_no "Continue anyway?" "n"; then
            exit 1
        fi
    fi
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot determine OS. /etc/os-release not found."
        exit 1
    fi
    
    source /etc/os-release
    log_info "Detected OS: $PRETTY_NAME"
    
    # Check architecture
    local arch=$(uname -m)
    if [[ "$arch" != "x86_64" ]] && [[ "$arch" != "aarch64" ]]; then
        log_warning "Unsupported architecture: $arch"
    fi
    
    # Check disk space (minimum 20GB free)
    local free_space=$(df -BG "$PROJECT_ROOT" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ "$free_space" -lt 20 ]]; then
        log_warning "Low disk space: ${free_space}GB available (20GB+ recommended)"
        if ! prompt_yes_no "Continue anyway?" "n"; then
            exit 1
        fi
    fi
    
    # Check memory (minimum 4GB)
    local total_mem=$(free -g | awk '/^Mem:/{print $2}')
    if [[ "$total_mem" -lt 4 ]]; then
        log_warning "Low memory: ${total_mem}GB available (4GB+ recommended)"
        if ! prompt_yes_no "Continue anyway?" "n"; then
            exit 1
        fi
    fi
    
    # Check required commands
    local required_cmds=("curl" "git" "openssl" "awk" "sed")
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done
    
    log_success "System requirements check completed"
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        return 1
    fi
    
    if ! docker ps &> /dev/null; then
        log_warning "Docker is installed but not accessible. May need sudo or user group configuration."
        return 1
    fi
    
    local docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
    if version_gt "$MIN_DOCKER_VERSION" "$docker_version"; then
        log_warning "Docker version $docker_version is below minimum $MIN_DOCKER_VERSION"
        return 1
    fi
    
    if ! docker compose version &> /dev/null; then
        log_warning "Docker Compose plugin not found"
        return 1
    fi
    
    log_success "Docker check passed (version: $docker_version)"
    return 0
}

install_docker() {
    log_step "Installing Docker"
    
    source /etc/os-release
    
    case "$ID" in
        ubuntu|debian)
            sudo apt-get update
            sudo apt-get install -y ca-certificates curl gnupg
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$ID/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            sudo chmod a+r /etc/apt/keyrings/docker.gpg
            
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
                sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        centos|rhel|fedora)
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            sudo systemctl start docker
            sudo systemctl enable docker
            ;;
        *)
            log_error "Unsupported OS for automatic Docker installation: $ID"
            log_info "Please install Docker manually: https://docs.docker.com/engine/install/"
            exit 1
            ;;
    esac
    
    # Add user to docker group if not root
    if [[ $EUID -ne 0 ]]; then
        sudo usermod -aG docker "$USER"
        log_warning "User added to docker group. You may need to log out and back in for this to take effect."
        log_info "Or run: newgrp docker"
    fi
    
    log_success "Docker installed successfully"
}

################################################################################
# CONFIGURATION STEPS
################################################################################

step_01_installation_type() {
    log_step "Step 1/27: Installation Type"
    
    echo "Select installation type:"
    echo "1) Quick Start (Recommended defaults)"
    echo "2) Custom Installation (Full configuration)"
    echo "3) Minimal (Ollama + WebUI only)"
    echo "4) Development (All services with debug enabled)"
    
    local choice
    read -rp "Enter choice [1-4]: " choice
    
    case "$choice" in
        1)
            CONFIG_VALUES[INSTALL_TYPE]="quick"
            CONFIG_VALUES[INSTALL_OLLAMA]="true"
            CONFIG_VALUES[INSTALL_WEBUI]="true"
            CONFIG_VALUES[INSTALL_N8N]="true"
            CONFIG_VALUES[INSTALL_POSTGRES]="true"
            CONFIG_VALUES[INSTALL_REDIS]="false"
            CONFIG_VALUES[INSTALL_NGINX]="true"
            CONFIG_VALUES[INSTALL_MONITORING]="false"
            ;;
        2)
            CONFIG_VALUES[INSTALL_TYPE]="custom"
            ;;
        3)
            CONFIG_VALUES[INSTALL_TYPE]="minimal"
            CONFIG_VALUES[INSTALL_OLLAMA]="true"
            CONFIG_VALUES[INSTALL_WEBUI]="true"
            CONFIG_VALUES[INSTALL_N8N]="false"
            CONFIG_VALUES[INSTALL_POSTGRES]="false"
            CONFIG_VALUES[INSTALL_REDIS]="false"
            CONFIG_VALUES[INSTALL_NGINX]="false"
            CONFIG_VALUES[INSTALL_MONITORING]="false"
            ;;
        4)
            CONFIG_VALUES[INSTALL_TYPE]="development"
            CONFIG_VALUES[INSTALL_OLLAMA]="true"
            CONFIG_VALUES[INSTALL_WEBUI]="true"
            CONFIG_VALUES[INSTALL_N8N]="true"
            CONFIG_VALUES[INSTALL_POSTGRES]="true"
            CONFIG_VALUES[INSTALL_REDIS]="true"
            CONFIG_VALUES[INSTALL_NGINX]="true"
            CONFIG_VALUES[INSTALL_MONITORING]="true"
            CONFIG_VALUES[DEBUG_MODE]="true"
            ;;
        *)
            log_error "Invalid choice"
            step_01_installation_type
            return
            ;;
    esac
    
    log_success "Installation type: ${CONFIG_VALUES[INSTALL_TYPE]}"
}

step_02_project_info() {
    log_step "Step 2/27: Project Information"
    
    CONFIG_VALUES[PROJECT_NAME]=$(prompt_with_default "Project name" "aiplatform")
    CONFIG_VALUES[ENVIRONMENT]=$(prompt_with_default "Environment (dev/staging/prod)" "prod")
    CONFIG_VALUES[ADMIN_EMAIL]=$(prompt_with_default "Administrator email" "admin@example.com")
    
    while ! validate_email "${CONFIG_VALUES[ADMIN_EMAIL]}"; do
        log_warning "Invalid email format"
        CONFIG_VALUES[ADMIN_EMAIL]=$(prompt_with_default "Administrator email" "admin@example.com")
    done
    
    log_success "Project info configured"
}

step_03_stack_selection() {
    if [[ "${CONFIG_VALUES[INSTALL_TYPE]}" != "custom" ]]; then
        return
    fi
    
    log_step "Step 3/27: Stack Component Selection"
    
    CONFIG_VALUES[INSTALL_OLLAMA]=$(prompt_yes_no "Install Ollama?" "y" && echo "true" || echo "false")
    CONFIG_VALUES[INSTALL_WEBUI]=$(prompt_yes_no "Install Open WebUI?" "y" && echo "true" || echo "false")
    CONFIG_VALUES[INSTALL_N8N]=$(prompt_yes_no "Install n8n?" "y" && echo "true" || echo "false")
    CONFIG_VALUES[INSTALL_POSTGRES]=$(prompt_yes_no "Install PostgreSQL?" "y" && echo "true" || echo "false")
    CONFIG_VALUES[INSTALL_REDIS]=$(prompt_yes_no "Install Redis?" "n" && echo "true" || echo "false")
    CONFIG_VALUES[INSTALL_NGINX]=$(prompt_yes_no "Install Nginx reverse proxy?" "y" && echo "true" || echo "false")
    CONFIG_VALUES[INSTALL_MONITORING]=$(prompt_yes_no "Install monitoring stack (Prometheus/Grafana)?" "n" && echo "true" || echo "false")
    
    log_success "Stack components selected"
}

step_04_service_ports() {
    log_step "Step 4/27: Service Ports Configuration"
    
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        CONFIG_VALUES[OLLAMA_PORT]=$(prompt_with_default "Ollama API port" "11434")
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]]; then
        CONFIG_VALUES[WEBUI_PORT]=$(prompt_with_default "WebUI port" "3000")
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        CONFIG_VALUES[N8N_PORT]=$(prompt_with_default "n8n port" "5678")
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
        CONFIG_VALUES[POSTGRES_PORT]=$(prompt_with_default "PostgreSQL port" "5432")
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
        CONFIG_VALUES[REDIS_PORT]=$(prompt_with_default "Redis port" "6379")
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_NGINX]}" == "true" ]]; then
        CONFIG_VALUES[NGINX_HTTP_PORT]=$(prompt_with_default "Nginx HTTP port" "80")
        CONFIG_VALUES[NGINX_HTTPS_PORT]=$(prompt_with_default "Nginx HTTPS port" "443")
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_MONITORING]}" == "true" ]]; then
        CONFIG_VALUES[PROMETHEUS_PORT]=$(prompt_with_default "Prometheus port" "9090")
        CONFIG_VALUES[GRAFANA_PORT]=$(prompt_with_default "Grafana port" "3001")
    fi
    
    log_success "Service ports configured"
}

step_05_storage_config() {
    log_step "Step 5/27: Storage Configuration"
    
    CONFIG_VALUES[DATA_DIR]=$(prompt_with_default "Data directory path" "/var/lib/aiplatform")
    CONFIG_VALUES[BACKUP_ENABLED]=$(prompt_yes_no "Enable automated backups?" "y" && echo "true" || echo "false")
    
    if [[ "${CONFIG_VALUES[BACKUP_ENABLED]}" == "true" ]]; then
        CONFIG_VALUES[BACKUP_RETENTION_DAYS]=$(prompt_with_default "Backup retention days" "7")
        CONFIG_VALUES[BACKUP_SCHEDULE]=$(prompt_with_default "Backup cron schedule" "0 2 * * *")
    fi
    
    CONFIG_VALUES[LOG_RETENTION_DAYS]=$(prompt_with_default "Log retention days" "30")
    
    log_success "Storage configured"
}
step_06_database_config() {
    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" != "true" ]]; then
        return
    fi
    
    log_step "Step 6/27: Database Configuration"
    
    CONFIG_VALUES[POSTGRES_DB]=$(prompt_with_default "PostgreSQL database name" "aiplatform")
    CONFIG_VALUES[POSTGRES_USER]=$(prompt_with_default "PostgreSQL username" "aiplatform")
    
    if prompt_yes_no "Auto-generate PostgreSQL password?" "y"; then
        CONFIG_VALUES[POSTGRES_PASSWORD]=$(generate_random_password 32)
        log_info "Generated password: ${CONFIG_VALUES[POSTGRES_PASSWORD]}"
    else
        read -rsp "Enter PostgreSQL password: " pg_pass
        echo
        CONFIG_VALUES[POSTGRES_PASSWORD]="$pg_pass"
    fi
    
    CONFIG_VALUES[POSTGRES_MAX_CONNECTIONS]=$(prompt_with_default "Max database connections" "100")
    CONFIG_VALUES[POSTGRES_SHARED_BUFFERS]=$(prompt_with_default "Shared buffers (MB)" "256")
    
    log_success "Database configured"
}

step_07_proxy_config() {
    if [[ "${CONFIG_VALUES[INSTALL_NGINX]}" != "true" ]]; then
        return
    fi
    
    log_step "Step 7/27: Reverse Proxy Configuration"
    
    CONFIG_VALUES[ENABLE_SSL]=$(prompt_yes_no "Enable SSL/TLS?" "y" && echo "true" || echo "false")
    
    if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]]; then
        CONFIG_VALUES[SSL_METHOD]="letsencrypt"
        if prompt_yes_no "Use Let's Encrypt for SSL?" "y"; then
            CONFIG_VALUES[SSL_METHOD]="letsencrypt"
            CONFIG_VALUES[SSL_EMAIL]=$(prompt_with_default "Email for Let's Encrypt" "${CONFIG_VALUES[ADMIN_EMAIL]}")
        else
            CONFIG_VALUES[SSL_METHOD]="custom"
            log_info "You'll need to provide SSL certificate files later"
        fi
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]]; then
        CONFIG_VALUES[WEBUI_DOMAIN]=$(prompt_with_default "WebUI domain (optional, blank for IP)" "")
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        CONFIG_VALUES[N8N_DOMAIN]=$(prompt_with_default "n8n domain (optional, blank for IP)" "")
    fi
    
    CONFIG_VALUES[CLIENT_MAX_BODY_SIZE]=$(prompt_with_default "Max upload size (MB)" "100")
    
    log_success "Proxy configured"
}

step_08_backup_config() {
    if [[ "${CONFIG_VALUES[BACKUP_ENABLED]}" != "true" ]]; then
        return
    fi
    
    log_step "Step 8/27: Backup Strategy"
    
    echo "Select backup storage:"
    echo "1) Local filesystem"
    echo "2) AWS S3"
    echo "3) MinIO"
    echo "4) Both local and remote"
    
    local choice
    read -rp "Enter choice [1-4]: " choice
    
    case "$choice" in
        1) CONFIG_VALUES[BACKUP_STORAGE]="local" ;;
        2) 
            CONFIG_VALUES[BACKUP_STORAGE]="s3"
            CONFIG_VALUES[S3_BUCKET]=$(prompt_with_default "S3 bucket name" "")
            CONFIG_VALUES[S3_REGION]=$(prompt_with_default "S3 region" "us-east-1")
            read -rp "AWS Access Key ID: " CONFIG_VALUES[AWS_ACCESS_KEY_ID]
            read -rsp "AWS Secret Access Key: " CONFIG_VALUES[AWS_SECRET_ACCESS_KEY]
            echo
            ;;
        3)
            CONFIG_VALUES[BACKUP_STORAGE]="minio"
            CONFIG_VALUES[MINIO_ENDPOINT]=$(prompt_with_default "MinIO endpoint" "")
            CONFIG_VALUES[MINIO_BUCKET]=$(prompt_with_default "MinIO bucket" "backups")
            read -rp "MinIO Access Key: " CONFIG_VALUES[MINIO_ACCESS_KEY]
            read -rsp "MinIO Secret Key: " CONFIG_VALUES[MINIO_SECRET_KEY]
            echo
            ;;
        4)
            CONFIG_VALUES[BACKUP_STORAGE]="both"
            CONFIG_VALUES[S3_BUCKET]=$(prompt_with_default "S3 bucket name" "")
            CONFIG_VALUES[S3_REGION]=$(prompt_with_default "S3 region" "us-east-1")
            read -rp "AWS Access Key ID: " CONFIG_VALUES[AWS_ACCESS_KEY_ID]
            read -rsp "AWS Secret Access Key: " CONFIG_VALUES[AWS_SECRET_ACCESS_KEY]
            echo
            ;;
        *)
            log_error "Invalid choice"
            step_08_backup_config
            return
            ;;
    esac
    
    CONFIG_VALUES[BACKUP_COMPRESSION]=$(prompt_yes_no "Enable backup compression?" "y" && echo "true" || echo "false")
    CONFIG_VALUES[BACKUP_ENCRYPTION]=$(prompt_yes_no "Enable backup encryption?" "y" && echo "true" || echo "false")
    
    if [[ "${CONFIG_VALUES[BACKUP_ENCRYPTION]}" == "true" ]]; then
        if prompt_yes_no "Auto-generate encryption key?" "y"; then
            CONFIG_VALUES[BACKUP_ENCRYPTION_KEY]=$(generate_random_password 32)
            log_warning "SAVE THIS KEY: ${CONFIG_VALUES[BACKUP_ENCRYPTION_KEY]}"
        else
            read -rsp "Enter encryption key: " CONFIG_VALUES[BACKUP_ENCRYPTION_KEY]
            echo
        fi
    fi
    
    log_success "Backup strategy configured"
}

step_09_logging_config() {
    log_step "Step 9/27: Logging Configuration"
    
    echo "Select log level:"
    echo "1) ERROR (minimal)"
    echo "2) WARNING"
    echo "3) INFO (recommended)"
    echo "4) DEBUG (verbose)"
    
    local choice
    read -rp "Enter choice [1-4]: " choice
    
    case "$choice" in
        1) CONFIG_VALUES[LOG_LEVEL]="ERROR" ;;
        2) CONFIG_VALUES[LOG_LEVEL]="WARNING" ;;
        3) CONFIG_VALUES[LOG_LEVEL]="INFO" ;;
        4) CONFIG_VALUES[LOG_LEVEL]="DEBUG" ;;
        *) CONFIG_VALUES[LOG_LEVEL]="INFO" ;;
    esac
    
    CONFIG_VALUES[LOG_FORMAT]=$(prompt_with_default "Log format (json/text)" "json")
    CONFIG_VALUES[LOG_MAX_SIZE]=$(prompt_with_default "Max log file size (MB)" "100")
    CONFIG_VALUES[LOG_MAX_FILES]=$(prompt_with_default "Max log files to keep" "10")
    
    CONFIG_VALUES[ENABLE_ACCESS_LOGS]=$(prompt_yes_no "Enable access logs?" "y" && echo "true" || echo "false")
    CONFIG_VALUES[ENABLE_AUDIT_LOGS]=$(prompt_yes_no "Enable audit logs?" "y" && echo "true" || echo "false")
    
    log_success "Logging configured"
}

step_10_resource_limits() {
    log_step "Step 10/27: Resource Limits"
    
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        CONFIG_VALUES[OLLAMA_MEMORY_LIMIT]=$(prompt_with_default "Ollama memory limit (GB)" "8")
        CONFIG_VALUES[OLLAMA_CPU_LIMIT]=$(prompt_with_default "Ollama CPU cores" "4")
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]]; then
        CONFIG_VALUES[WEBUI_MEMORY_LIMIT]=$(prompt_with_default "WebUI memory limit (GB)" "2")
        CONFIG_VALUES[WEBUI_CPU_LIMIT]=$(prompt_with_default "WebUI CPU cores" "2")
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        CONFIG_VALUES[N8N_MEMORY_LIMIT]=$(prompt_with_default "n8n memory limit (GB)" "2")
        CONFIG_VALUES[N8N_CPU_LIMIT]=$(prompt_with_default "n8n CPU cores" "2")
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
        CONFIG_VALUES[POSTGRES_MEMORY_LIMIT]=$(prompt_with_default "PostgreSQL memory limit (GB)" "2")
        CONFIG_VALUES[POSTGRES_CPU_LIMIT]=$(prompt_with_default "PostgreSQL CPU cores" "2")
    fi
    
    log_success "Resource limits configured"
}

step_11_network_config() {
    log_step "Step 11/27: Network Configuration"
    
    CONFIG_VALUES[DOCKER_NETWORK]=$(prompt_with_default "Docker network name" "aiplatform_network")
    CONFIG_VALUES[NETWORK_SUBNET]=$(prompt_with_default "Network subnet" "172.28.0.0/16")
    
    CONFIG_VALUES[ENABLE_IPV6]=$(prompt_yes_no "Enable IPv6?" "n" && echo "true" || echo "false")
    
    if [[ "${CONFIG_VALUES[ENABLE_IPV6]}" == "true" ]]; then
        CONFIG_VALUES[IPV6_SUBNET]=$(prompt_with_default "IPv6 subnet" "fd00::/80")
    fi
    
    CONFIG_VALUES[DNS_SERVERS]=$(prompt_with_default "Custom DNS servers (comma-separated, blank for default)" "")
    
    log_success "Network configured"
}

step_12_timezone_config() {
    log_step "Step 12/27: Timezone & Localization"
    
    local system_tz=$(timedatectl show -p Timezone --value 2>/dev/null || echo "UTC")
    CONFIG_VALUES[TIMEZONE]=$(prompt_with_default "Timezone" "$system_tz")
    
    CONFIG_VALUES[DEFAULT_LANGUAGE]=$(prompt_with_default "Default language" "en-US")
    
    log_success "Timezone configured"
}

step_13_auth_config() {
    log_step "Step 13/27: Authentication Configuration"
    
    if [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]]; then
        CONFIG_VALUES[WEBUI_AUTH_METHOD]="local"
        
        if prompt_yes_no "Enable OAuth authentication?" "n"; then
            CONFIG_VALUES[ENABLE_OAUTH]="true"
            
            echo "Select OAuth provider:"
            echo "1) Google"
            echo "2) GitHub"
            echo "3) Microsoft"
            echo "4) Generic OIDC"
            
            read -rp "Enter choice [1-4]: " oauth_choice
            
            case "$oauth_choice" in
                1) CONFIG_VALUES[OAUTH_PROVIDER]="google" ;;
                2) CONFIG_VALUES[OAUTH_PROVIDER]="github" ;;
                3) CONFIG_VALUES[OAUTH_PROVIDER]="microsoft" ;;
                4) CONFIG_VALUES[OAUTH_PROVIDER]="oidc" ;;
            esac
            
            read -rp "OAuth Client ID: " CONFIG_VALUES[OAUTH_CLIENT_ID]
            read -rsp "OAuth Client Secret: " CONFIG_VALUES[OAUTH_CLIENT_SECRET]
            echo
            
            if [[ "${CONFIG_VALUES[OAUTH_PROVIDER]}" == "oidc" ]]; then
                CONFIG_VALUES[OAUTH_ISSUER_URL]=$(prompt_with_default "OIDC Issuer URL" "")
            fi
        else
            CONFIG_VALUES[ENABLE_OAUTH]="false"
        fi
        
        CONFIG_VALUES[WEBUI_SIGNUP_ENABLED]=$(prompt_yes_no "Allow user self-registration?" "y" && echo "true" || echo "false")
        
        if [[ "${CONFIG_VALUES[WEBUI_SIGNUP_ENABLED]}" == "true" ]]; then
            CONFIG_VALUES[WEBUI_REQUIRE_EMAIL_VERIFICATION]=$(prompt_yes_no "Require email verification?" "y" && echo "true" || echo "false")
        fi
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        CONFIG_VALUES[N8N_BASIC_AUTH_ACTIVE]=$(prompt_yes_no "Enable n8n basic auth?" "y" && echo "true" || echo "false")
        
        if [[ "${CONFIG_VALUES[N8N_BASIC_AUTH_ACTIVE]}" == "true" ]]; then
            CONFIG_VALUES[N8N_BASIC_AUTH_USER]=$(prompt_with_default "n8n username" "admin")
            
            if prompt_yes_no "Auto-generate n8n password?" "y"; then
                CONFIG_VALUES[N8N_BASIC_AUTH_PASSWORD]=$(generate_random_password 16)
                log_info "Generated n8n password: ${CONFIG_VALUES[N8N_BASIC_AUTH_PASSWORD]}"
            else
                read -rsp "Enter n8n password: " CONFIG_VALUES[N8N_BASIC_AUTH_PASSWORD]
                echo
            fi
        fi
    fi
    
    # Generate encryption key for WebUI
    if [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]]; then
        CONFIG_VALUES[WEBUI_SECRET_KEY]=$(generate_random_password 32)
    fi
    
    # Generate encryption key for n8n
    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        CONFIG_VALUES[N8N_ENCRYPTION_KEY]=$(generate_random_password 32)
    fi
    
    log_success "Authentication configured"
}

step_14_model_selection() {
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" != "true" ]]; then
        return
    fi
    
    log_step "Step 14/27: AI Model Selection"
    
    echo "Select models to download (comma-separated numbers):"
    echo "1) llama3.2 (3B) - Fast, general purpose"
    echo "2) llama3.2:1b - Very fast, lightweight"
    echo "3) phi3 (3.8B) - Microsoft's efficient model"
    echo "4) mistral (7B) - Balanced performance"
    echo "5) llama3.1:8b - Latest LLaMA, good quality"
    echo "6) codellama (7B) - Code generation"
    echo "7) qwen2.5:7b - Multilingual support"
    echo "8) gemma2:9b - Google's latest"
    echo "9) Custom (specify manually)"
    echo "0) Skip (download later)"
    
    read -rp "Enter selections: " model_choices
    
    local models=()
    IFS=',' read -ra CHOICES <<< "$model_choices"
    
    for choice in "${CHOICES[@]}"; do
        choice=$(echo "$choice" | tr -d ' ')
        case "$choice" in
            1) models+=("llama3.2") ;;
            2) models+=("llama3.2:1b") ;;
            3) models+=("phi3") ;;
            4) models+=("mistral") ;;
            5) models+=("llama3.1:8b") ;;
            6) models+=("codellama") ;;
            7) models+=("qwen2.5:7b") ;;
            8) models+=("gemma2:9b") ;;
            9) 
                read -rp "Enter custom model names (comma-separated): " custom_models
                IFS=',' read -ra CUSTOM <<< "$custom_models"
                for model in "${CUSTOM[@]}"; do
                    models+=("$(echo "$model" | tr -d ' ')")
                done
                ;;
            0) ;;
            *) log_warning "Invalid choice: $choice" ;;
        esac
    done
    
    CONFIG_VALUES[OLLAMA_MODELS]=$(IFS=,; echo "${models[*]}")
    
    if [[ -n "${CONFIG_VALUES[OLLAMA_MODELS]}" ]]; then
        log_info "Selected models: ${CONFIG_VALUES[OLLAMA_MODELS]}"
    fi
    
    log_success "Model selection configured"
}

step_15_model_settings() {
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" != "true" ]]; then
        return
    fi
    
    log_step "Step 15/27: AI Model Settings"
    
    # GPU Configuration
    CONFIG_VALUES[OLLAMA_GPU_ENABLED]=$(prompt_yes_no "Enable GPU acceleration?" "n" && echo "true" || echo "false")
    
    if [[ "${CONFIG_VALUES[OLLAMA_GPU_ENABLED]}" == "true" ]]; then
        echo "Select GPU type:"
        echo "1) NVIDIA (CUDA)"
        echo "2) AMD (ROCm)"
        echo "3) Apple Silicon (Metal)"
        
        local gpu_choice
        read -rp "Enter choice [1-3]: " gpu_choice
        
        case "$gpu_choice" in
            1) CONFIG_VALUES[OLLAMA_GPU_TYPE]="nvidia" ;;
            2) CONFIG_VALUES[OLLAMA_GPU_TYPE]="amd" ;;
            3) CONFIG_VALUES[OLLAMA_GPU_TYPE]="metal" ;;
            *) CONFIG_VALUES[OLLAMA_GPU_TYPE]="nvidia" ;;
        esac
        
        if [[ "${CONFIG_VALUES[OLLAMA_GPU_TYPE]}" == "nvidia" ]]; then
            CONFIG_VALUES[OLLAMA_GPU_LAYERS]=$(prompt_with_default "Number of layers to offload to GPU (-1 for all)" "-1")
        fi
    fi
    
    # Model Performance Settings
    CONFIG_VALUES[OLLAMA_NUM_PARALLEL]=$(prompt_with_default "Number of parallel model loads" "1")
    CONFIG_VALUES[OLLAMA_MAX_LOADED_MODELS]=$(prompt_with_default "Max models to keep in memory" "1")
    CONFIG_VALUES[OLLAMA_KEEP_ALIVE]=$(prompt_with_default "Model keep-alive duration (e.g., 5m, 1h)" "5m")
    
    # Context Settings
    CONFIG_VALUES[OLLAMA_NUM_CTX]=$(prompt_with_default "Default context window size" "2048")
    CONFIG_VALUES[OLLAMA_NUM_THREAD]=$(prompt_with_default "Number of CPU threads" "4")
    
    log_success "Model settings configured"
}
step_16_monitoring_config() {
    if [[ "${CONFIG_VALUES[INSTALL_MONITORING]}" != "true" ]]; then
        return
    fi
    
    log_step "Step 16/27: Monitoring Configuration"
    
    CONFIG_VALUES[PROMETHEUS_RETENTION]=$(prompt_with_default "Prometheus retention period (days)" "15")
    CONFIG_VALUES[PROMETHEUS_SCRAPE_INTERVAL]=$(prompt_with_default "Metrics scrape interval (seconds)" "15")
    
    CONFIG_VALUES[GRAFANA_ADMIN_USER]=$(prompt_with_default "Grafana admin username" "admin")
    
    if prompt_yes_no "Auto-generate Grafana admin password?" "y"; then
        CONFIG_VALUES[GRAFANA_ADMIN_PASSWORD]=$(generate_random_password 16)
        log_info "Generated Grafana password: ${CONFIG_VALUES[GRAFANA_ADMIN_PASSWORD]}"
    else
        read -rsp "Enter Grafana admin password: " CONFIG_VALUES[GRAFANA_ADMIN_PASSWORD]
        echo
    fi
    
    CONFIG_VALUES[ENABLE_ALERTING]=$(prompt_yes_no "Enable alerting?" "y" && echo "true" || echo "false")
    
    if [[ "${CONFIG_VALUES[ENABLE_ALERTING]}" == "true" ]]; then
        echo "Select alert notification method:"
        echo "1) Email"
        echo "2) Slack"
        echo "3) Discord"
        echo "4) Webhook"
        echo "5) Multiple"
        
        local alert_choice
        read -rp "Enter choice [1-5]: " alert_choice
        
        case "$alert_choice" in
            1)
                CONFIG_VALUES[ALERT_METHOD]="email"
                CONFIG_VALUES[ALERT_EMAIL_TO]=$(prompt_with_default "Alert recipient email" "${CONFIG_VALUES[ADMIN_EMAIL]}")
                CONFIG_VALUES[ALERT_EMAIL_FROM]=$(prompt_with_default "Alert sender email" "alerts@${CONFIG_VALUES[DOMAIN]:-localhost}")
                CONFIG_VALUES[SMTP_HOST]=$(prompt_with_default "SMTP host" "smtp.gmail.com")
                CONFIG_VALUES[SMTP_PORT]=$(prompt_with_default "SMTP port" "587")
                read -rp "SMTP username: " CONFIG_VALUES[SMTP_USER]
                read -rsp "SMTP password: " CONFIG_VALUES[SMTP_PASSWORD]
                echo
                ;;
            2)
                CONFIG_VALUES[ALERT_METHOD]="slack"
                read -rp "Slack webhook URL: " CONFIG_VALUES[SLACK_WEBHOOK_URL]
                CONFIG_VALUES[SLACK_CHANNEL]=$(prompt_with_default "Slack channel" "#alerts")
                ;;
            3)
                CONFIG_VALUES[ALERT_METHOD]="discord"
                read -rp "Discord webhook URL: " CONFIG_VALUES[DISCORD_WEBHOOK_URL]
                ;;
            4)
                CONFIG_VALUES[ALERT_METHOD]="webhook"
                read -rp "Webhook URL: " CONFIG_VALUES[ALERT_WEBHOOK_URL]
                ;;
            5)
                CONFIG_VALUES[ALERT_METHOD]="multiple"
                log_info "You can configure multiple methods in alertmanager.yml later"
                ;;
        esac
        
        CONFIG_VALUES[ALERT_CPU_THRESHOLD]=$(prompt_with_default "CPU usage alert threshold (%)" "80")
        CONFIG_VALUES[ALERT_MEMORY_THRESHOLD]=$(prompt_with_default "Memory usage alert threshold (%)" "85")
        CONFIG_VALUES[ALERT_DISK_THRESHOLD]=$(prompt_with_default "Disk usage alert threshold (%)" "90")
    fi
    
    log_success "Monitoring configured"
}

step_17_email_config() {
    log_step "Step 17/27: Email Configuration"
    
    CONFIG_VALUES[ENABLE_EMAIL]=$(prompt_yes_no "Enable email functionality?" "y" && echo "true" || echo "false")
    
    if [[ "${CONFIG_VALUES[ENABLE_EMAIL]}" == "true" ]]; then
        if [[ -z "${CONFIG_VALUES[SMTP_HOST]:-}" ]]; then
            CONFIG_VALUES[SMTP_HOST]=$(prompt_with_default "SMTP host" "smtp.gmail.com")
            CONFIG_VALUES[SMTP_PORT]=$(prompt_with_default "SMTP port" "587")
            read -rp "SMTP username: " CONFIG_VALUES[SMTP_USER]
            read -rsp "SMTP password: " CONFIG_VALUES[SMTP_PASSWORD]
            echo
        fi
        
        CONFIG_VALUES[SMTP_FROM_NAME]=$(prompt_with_default "Email sender name" "AI Platform")
        CONFIG_VALUES[SMTP_FROM_EMAIL]=$(prompt_with_default "Email sender address" "noreply@${CONFIG_VALUES[DOMAIN]:-localhost}")
        CONFIG_VALUES[SMTP_USE_TLS]=$(prompt_yes_no "Use TLS?" "y" && echo "true" || echo "false")
    fi
    
    log_success "Email configured"
}

step_18_security_config() {
    log_step "Step 18/27: Security Configuration"
    
    CONFIG_VALUES[ENABLE_RATE_LIMITING]=$(prompt_yes_no "Enable rate limiting?" "y" && echo "true" || echo "false")
    
    if [[ "${CONFIG_VALUES[ENABLE_RATE_LIMITING]}" == "true" ]]; then
        CONFIG_VALUES[RATE_LIMIT_REQUESTS]=$(prompt_with_default "Max requests per minute" "60")
        CONFIG_VALUES[RATE_LIMIT_BURST]=$(prompt_with_default "Burst size" "20")
    fi
    
    CONFIG_VALUES[ENABLE_CORS]=$(prompt_yes_no "Enable CORS?" "y" && echo "true" || echo "false")
    
    if [[ "${CONFIG_VALUES[ENABLE_CORS]}" == "true" ]]; then
        CONFIG_VALUES[CORS_ORIGINS]=$(prompt_with_default "Allowed CORS origins (comma-separated)" "*")
    fi
    
    CONFIG_VALUES[ENABLE_FIREWALL]=$(prompt_yes_no "Configure UFW firewall rules?" "y" && echo "true" || echo "false")
    
    CONFIG_VALUES[ENABLE_FAIL2BAN]=$(prompt_yes_no "Install and configure Fail2ban?" "y" && echo "true" || echo "false")
    
    CONFIG_VALUES[ENABLE_SECURITY_HEADERS]=$(prompt_yes_no "Enable security headers?" "y" && echo "true" || echo "false")
    
    log_success "Security configured"
}

step_19_performance_config() {
    log_step "Step 19/27: Performance Tuning"
    
    CONFIG_VALUES[ENABLE_CACHING]=$(prompt_yes_no "Enable Redis caching?" "y" && echo "true" || echo "false")
    
    if [[ "${CONFIG_VALUES[ENABLE_CACHING]}" == "true" ]]; then
        CONFIG_VALUES[CACHE_TTL]=$(prompt_with_default "Cache TTL (seconds)" "3600")
        CONFIG_VALUES[REDIS_MAX_MEMORY]=$(prompt_with_default "Redis max memory (MB)" "256")
        
        echo "Select Redis eviction policy:"
        echo "1) allkeys-lru (recommended)"
        echo "2) volatile-lru"
        echo "3) allkeys-lfu"
        echo "4) volatile-lfu"
        
        local eviction_choice
        read -rp "Enter choice [1-4]: " eviction_choice
        
        case "$eviction_choice" in
            1) CONFIG_VALUES[REDIS_EVICTION_POLICY]="allkeys-lru" ;;
            2) CONFIG_VALUES[REDIS_EVICTION_POLICY]="volatile-lru" ;;
            3) CONFIG_VALUES[REDIS_EVICTION_POLICY]="allkeys-lfu" ;;
            4) CONFIG_VALUES[REDIS_EVICTION_POLICY]="volatile-lfu" ;;
            *) CONFIG_VALUES[REDIS_EVICTION_POLICY]="allkeys-lru" ;;
        esac
    fi
    
    CONFIG_VALUES[ENABLE_COMPRESSION]=$(prompt_yes_no "Enable response compression?" "y" && echo "true" || echo "false")
    
    if [[ "${CONFIG_VALUES[ENABLE_COMPRESSION]}" == "true" ]]; then
        CONFIG_VALUES[COMPRESSION_LEVEL]=$(prompt_with_default "Compression level (1-9)" "6")
    fi
    
    CONFIG_VALUES[CONNECTION_POOL_SIZE]=$(prompt_with_default "Database connection pool size" "20")
    CONFIG_VALUES[WORKER_PROCESSES]=$(prompt_with_default "Number of worker processes" "auto")
    
    log_success "Performance configured"
}

step_20_update_config() {
    log_step "Step 20/27: Update Strategy"
    
    CONFIG_VALUES[AUTO_UPDATE]=$(prompt_yes_no "Enable automatic updates?" "n" && echo "true" || echo "false")
    
    if [[ "${CONFIG_VALUES[AUTO_UPDATE]}" == "true" ]]; then
        echo "Select update schedule:"
        echo "1) Daily at 2 AM"
        echo "2) Weekly on Sunday at 2 AM"
        echo "3) Monthly on 1st at 2 AM"
        echo "4) Custom cron"
        
        local update_choice
        read -rp "Enter choice [1-4]: " update_choice
        
        case "$update_choice" in
            1) CONFIG_VALUES[UPDATE_SCHEDULE]="0 2 * * *" ;;
            2) CONFIG_VALUES[UPDATE_SCHEDULE]="0 2 * * 0" ;;
            3) CONFIG_VALUES[UPDATE_SCHEDULE]="0 2 1 * *" ;;
            4) 
                read -rp "Enter cron expression: " CONFIG_VALUES[UPDATE_SCHEDULE]
                ;;
            *) CONFIG_VALUES[UPDATE_SCHEDULE]="0 2 * * 0" ;;
        esac
        
        CONFIG_VALUES[UPDATE_NOTIFICATION]=$(prompt_yes_no "Send update notifications?" "y" && echo "true" || echo "false")
    fi
    
    CONFIG_VALUES[BACKUP_BEFORE_UPDATE]=$(prompt_yes_no "Backup before updates?" "y" && echo "true" || echo "false")
    
    log_success "Update strategy configured"
}

step_21_development_config() {
    log_step "Step 21/27: Development Settings"
    
    CONFIG_VALUES[ENABLE_DEBUG_MODE]=$(prompt_yes_no "Enable debug mode?" "n" && echo "true" || echo "false")
    CONFIG_VALUES[ENABLE_HOT_RELOAD]=$(prompt_yes_no "Enable hot reload (dev only)?" "n" && echo "true" || echo "false")
    CONFIG_VALUES[ENABLE_API_DOCS]=$(prompt_yes_no "Enable API documentation?" "y" && echo "true" || echo "false")
    
    if [[ "${CONFIG_VALUES[ENABLE_API_DOCS]}" == "true" ]]; then
        CONFIG_VALUES[API_DOCS_PATH]=$(prompt_with_default "API docs path" "/api/docs")
    fi
    
    log_success "Development settings configured"
}

step_22_webhook_config() {
    log_step "Step 22/27: Webhook Configuration"
    
    CONFIG_VALUES[ENABLE_WEBHOOKS]=$(prompt_yes_no "Enable webhooks?" "n" && echo "true" || echo "false")
    
    if [[ "${CONFIG_VALUES[ENABLE_WEBHOOKS]}" == "true" ]]; then
        CONFIG_VALUES[WEBHOOK_TIMEOUT]=$(prompt_with_default "Webhook timeout (seconds)" "30")
        CONFIG_VALUES[WEBHOOK_RETRY_COUNT]=$(prompt_with_default "Webhook retry attempts" "3")
        CONFIG_VALUES[WEBHOOK_RETRY_DELAY]=$(prompt_with_default "Webhook retry delay (seconds)" "5")
    fi
    
    log_success "Webhook configured"
}

step_23_api_keys() {
    log_step "Step 23/27: API Keys & External Services"
    
    if prompt_yes_no "Configure external API keys?" "n"; then
        read -rp "OpenAI API Key (optional): " CONFIG_VALUES[OPENAI_API_KEY]
        read -rp "Anthropic API Key (optional): " CONFIG_VALUES[ANTHROPIC_API_KEY]
        read -rp "Google AI API Key (optional): " CONFIG_VALUES[GOOGLE_AI_API_KEY]
        read -rp "Hugging Face API Key (optional): " CONFIG_VALUES[HUGGINGFACE_API_KEY]
    fi
    
    log_success "API keys configured"
}

step_24_custom_env() {
    log_step "Step 24/27: Custom Environment Variables"
    
    if prompt_yes_no "Add custom environment variables?" "n"; then
        echo "Enter custom variables (format: KEY=VALUE, one per line, empty line to finish):"
        
        local custom_vars=()
        while true; do
            read -rp "> " custom_var
            [[ -z "$custom_var" ]] && break
            custom_vars+=("$custom_var")
        done
        
        CONFIG_VALUES[CUSTOM_ENV_VARS]=$(IFS=$'\n'; echo "${custom_vars[*]}")
    fi
    
    log_success "Custom variables configured"
}

step_25_experimental_features() {
    log_step "Step 25/27: Experimental Features"
    
    CONFIG_VALUES[ENABLE_EXPERIMENTAL]=$(prompt_yes_no "Enable experimental features?" "n" && echo "true" || echo "false")
    
    if [[ "${CONFIG_VALUES[ENABLE_EXPERIMENTAL]}" == "true" ]]; then
        log_warning "Experimental features may be unstable"
        
        CONFIG_VALUES[EXPERIMENTAL_VISION]=$(prompt_yes_no "Enable vision models?" "n" && echo "true" || echo "false")
        CONFIG_VALUES[EXPERIMENTAL_EMBEDDINGS]=$(prompt_yes_no "Enable embeddings service?" "n" && echo "true" || echo "false")
        CONFIG_VALUES[EXPERIMENTAL_VECTOR_DB]=$(prompt_yes_no "Enable vector database?" "n" && echo "true" || echo "false")
        
        if [[ "${CONFIG_VALUES[EXPERIMENTAL_VECTOR_DB]}" == "true" ]]; then
            echo "Select vector database:"
            echo "1) Qdrant"
            echo "2) Weaviate"
            echo "3) Milvus"
            
            local vdb_choice
            read -rp "Enter choice [1-3]: " vdb_choice
            
            case "$vdb_choice" in
                1) CONFIG_VALUES[VECTOR_DB_TYPE]="qdrant" ;;
                2) CONFIG_VALUES[VECTOR_DB_TYPE]="weaviate" ;;
                3) CONFIG_VALUES[VECTOR_DB_TYPE]="milvus" ;;
                *) CONFIG_VALUES[VECTOR_DB_TYPE]="qdrant" ;;
            esac
        fi
    fi
    
    log_success "Experimental features configured"
}

step_26_review_config() {
    log_step "Step 26/27: Configuration Review"
    
    echo "=========================================="
    echo "Configuration Summary"
    echo "=========================================="
    echo
    echo "Environment: ${CONFIG_VALUES[ENVIRONMENT]}"
    echo "Domain: ${CONFIG_VALUES[DOMAIN]:-N/A}"
    echo "Admin Email: ${CONFIG_VALUES[ADMIN_EMAIL]}"
    echo
    echo "Services:"
    [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]] && echo "  ✓ Ollama"
    [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]] && echo "  ✓ Open WebUI"
    [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]] && echo "  ✓ n8n"
    [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]] && echo "  ✓ PostgreSQL"
    [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]] && echo "  ✓ Redis"
    [[ "${CONFIG_VALUES[INSTALL_NGINX]}" == "true" ]] && echo "  ✓ Nginx"
    [[ "${CONFIG_VALUES[INSTALL_MONITORING]}" == "true" ]] && echo "  ✓ Monitoring Stack"
    echo
    echo "Features:"
    [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]] && echo "  ✓ SSL/TLS"
    [[ "${CONFIG_VALUES[BACKUP_ENABLED]}" == "true" ]] && echo "  ✓ Automated Backups"
    [[ "${CONFIG_VALUES[ENABLE_ALERTING]}" == "true" ]] && echo "  ✓ Alerting"
    [[ "${CONFIG_VALUES[ENABLE_OAUTH]}" == "true" ]] && echo "  ✓ OAuth"
    [[ "${CONFIG_VALUES[ENABLE_FIREWALL]}" == "true" ]] && echo "  ✓ Firewall"
    echo
    echo "AI Models: ${CONFIG_VALUES[OLLAMA_MODELS]:-None selected}"
    [[ "${CONFIG_VALUES[OLLAMA_GPU_ENABLED]}" == "true" ]] && echo "GPU: ${CONFIG_VALUES[OLLAMA_GPU_TYPE]}"
    echo
    echo "=========================================="
    
    if ! prompt_yes_no "Proceed with this configuration?" "y"; then
        log_error "Configuration cancelled by user"
        exit 1
    fi
    
    log_success "Configuration approved"
}

step_27_save_config() {
    log_step "Step 27/27: Saving Configuration"
    
    local config_backup="${CONFIG_DIR}/config_${TIMESTAMP}.bak"
    
    # Backup existing config if present
    if [[ -f "${CONFIG_DIR}/.env" ]]; then
        cp "${CONFIG_DIR}/.env" "$config_backup"
        log_info "Backed up existing config to $config_backup"
    fi
    
    # Save configuration summary
    {
        echo "# AI Platform Configuration"
        echo "# Generated: $(date)"
        echo "# Version: ${VERSION}"
        echo
        for key in "${!CONFIG_VALUES[@]}"; do
            echo "${key}=${CONFIG_VALUES[$key]}"
        done
    } > "${CONFIG_DIR}/config_summary.txt"
    
    log_success "Configuration saved"
}

################################################################################
# CONFIGURATION FILE GENERATION FUNCTIONS
################################################################################

generate_env_file() {
    log_info "Generating .env file..."
    
    cat > "${CONFIG_DIR}/.env" <<EOF
# AI Platform Environment Configuration
# Generated: $(date)
# Version: ${VERSION}

# ==================== GENERAL ====================
ENVIRONMENT=${CONFIG_VALUES[ENVIRONMENT]}
PROJECT_NAME=aiplatform
COMPOSE_PROJECT_NAME=aiplatform
TZ=${CONFIG_VALUES[TIMEZONE]}
PUID=1000
PGID=1000

# ==================== DOMAIN & EMAIL ====================
DOMAIN=${CONFIG_VALUES[DOMAIN]:-localhost}
ADMIN_EMAIL=${CONFIG_VALUES[ADMIN_EMAIL]}

# ==================== OLLAMA ====================
EOF

    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/.env" <<EOF
OLLAMA_HOST=0.0.0.0:${CONFIG_VALUES[OLLAMA_PORT]}
OLLAMA_PORT=${CONFIG_VALUES[OLLAMA_PORT]}
OLLAMA_MODELS=${CONFIG_VALUES[OLLAMA_MODELS]:-}
OLLAMA_NUM_PARALLEL=${CONFIG_VALUES[OLLAMA_NUM_PARALLEL]:-1}
OLLAMA_MAX_LOADED_MODELS=${CONFIG_VALUES[OLLAMA_MAX_LOADED_MODELS]:-1}
OLLAMA_KEEP_ALIVE=${CONFIG_VALUES[OLLAMA_KEEP_ALIVE]:-5m}
OLLAMA_NUM_CTX=${CONFIG_VALUES[OLLAMA_NUM_CTX]:-2048}
OLLAMA_NUM_THREAD=${CONFIG_VALUES[OLLAMA_NUM_THREAD]:-4}
EOF

        if [[ "${CONFIG_VALUES[OLLAMA_GPU_ENABLED]}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/.env" <<EOF
OLLAMA_GPU_ENABLED=true
OLLAMA_GPU_TYPE=${CONFIG_VALUES[OLLAMA_GPU_TYPE]}
OLLAMA_GPU_LAYERS=${CONFIG_VALUES[OLLAMA_GPU_LAYERS]:--1}
EOF
        fi
    fi

    if [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/.env" <<EOF

# ==================== OPEN WEBUI ====================
WEBUI_PORT=${CONFIG_VALUES[WEBUI_PORT]}
WEBUI_SECRET_KEY=${CONFIG_VALUES[WEBUI_SECRET_KEY]}
WEBUI_AUTH_METHOD=${CONFIG_VALUES[WEBUI_AUTH_METHOD]:-local}
WEBUI_SIGNUP_ENABLED=${CONFIG_VALUES[WEBUI_SIGNUP_ENABLED]:-true}
WEBUI_DOMAIN=${CONFIG_VALUES[WEBUI_DOMAIN]:-}
EOF

        if [[ "${CONFIG_VALUES[ENABLE_OAUTH]}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/.env" <<EOF
OAUTH_CLIENT_ID=${CONFIG_VALUES[OAUTH_CLIENT_ID]}
OAUTH_CLIENT_SECRET=${CONFIG_VALUES[OAUTH_CLIENT_SECRET]}
OAUTH_PROVIDER=${CONFIG_VALUES[OAUTH_PROVIDER]}
EOF
            if [[ "${CONFIG_VALUES[OAUTH_PROVIDER]}" == "oidc" ]]; then
                echo "OAUTH_ISSUER_URL=${CONFIG_VALUES[OAUTH_ISSUER_URL]}" >> "${CONFIG_DIR}/.env"
            fi
        fi
    fi

    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/.env" <<EOF

# ==================== N8N ====================
N8N_PORT=${CONFIG_VALUES[N8N_PORT]}
N8N_ENCRYPTION_KEY=${CONFIG_VALUES[N8N_ENCRYPTION_KEY]}
N8N_BASIC_AUTH_ACTIVE=${CONFIG_VALUES[N8N_BASIC_AUTH_ACTIVE]:-false}
EOF
        if [[ "${CONFIG_VALUES[N8N_BASIC_AUTH_ACTIVE]}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/.env" <<EOF
N8N_BASIC_AUTH_USER=${CONFIG_VALUES[N8N_BASIC_AUTH_USER]}
N8N_BASIC_AUTH_PASSWORD=${CONFIG_VALUES[N8N_BASIC_AUTH_PASSWORD]}
EOF
        fi
        
        cat >> "${CONFIG_DIR}/.env" <<EOF
N8N_DOMAIN=${CONFIG_VALUES[N8N_DOMAIN]:-}
N8N_PROTOCOL=${CONFIG_VALUES[ENABLE_SSL]:+https}${CONFIG_VALUES[ENABLE_SSL]:-http}
N8N_HOST=\${N8N_DOMAIN:-localhost}
EOF
    fi

    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/.env" <<EOF

# ==================== POSTGRESQL ====================
POSTGRES_PORT=${CONFIG_VALUES[POSTGRES_PORT]}
POSTGRES_DB=${CONFIG_VALUES[POSTGRES_DB]}
POSTGRES_USER=${CONFIG_VALUES[POSTGRES_USER]}
POSTGRES_PASSWORD=${CONFIG_VALUES[POSTGRES_PASSWORD]}
POSTGRES_MAX_CONNECTIONS=${CONFIG_VALUES[POSTGRES_MAX_CONNECTIONS]:-100}
POSTGRES_SHARED_BUFFERS=${CONFIG_VALUES[POSTGRES_SHARED_BUFFERS]:-256MB}
DATABASE_URL=postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@postgres:\${POSTGRES_PORT}/\${POSTGRES_DB}
EOF
    fi

    if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/.env" <<EOF

# ==================== REDIS ====================
REDIS_PORT=${CONFIG_VALUES[REDIS_PORT]}
REDIS_MAX_MEMORY=${CONFIG_VALUES[REDIS_MAX_MEMORY]:-256}mb
REDIS_EVICTION_POLICY=${CONFIG_VALUES[REDIS_EVICTION_POLICY]:-allkeys-lru}
EOF
    fi

    if [[ "${CONFIG_VALUES[INSTALL_NGINX]}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/.env" <<EOF

# ==================== NGINX ====================
NGINX_HTTP_PORT=${CONFIG_VALUES[NGINX_HTTP_PORT]}
NGINX_HTTPS_PORT=${CONFIG_VALUES[NGINX_HTTPS_PORT]}
CLIENT_MAX_BODY_SIZE=${CONFIG_VALUES[CLIENT_MAX_BODY_SIZE]:-100}m
EOF
        
        if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/.env" <<EOF
SSL_ENABLED=true
SSL_METHOD=${CONFIG_VALUES[SSL_METHOD]}
EOF
            if [[ "${CONFIG_VALUES[SSL_METHOD]}" == "letsencrypt" ]]; then
                echo "SSL_EMAIL=${CONFIG_VALUES[SSL_EMAIL]}" >> "${CONFIG_DIR}/.env"
            fi
        fi
    fi

    if [[ "${CONFIG_VALUES[INSTALL_MONITORING]}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/.env" <<EOF

# ==================== MONITORING ====================
PROMETHEUS_PORT=${CONFIG_VALUES[PROMETHEUS_PORT]}
GRAFANA_PORT=${CONFIG_VALUES[GRAFANA_PORT]}
GRAFANA_ADMIN_USER=${CONFIG_VALUES[GRAFANA_ADMIN_USER]}
GRAFANA_ADMIN_PASSWORD=${CONFIG_VALUES[GRAFANA_ADMIN_PASSWORD]}
PROMETHEUS_RETENTION=${CONFIG_VALUES[PROMETHEUS_RETENTION]:-15d}
PROMETHEUS_SCRAPE_INTERVAL=${CONFIG_VALUES[PROMETHEUS_SCRAPE_INTERVAL]:-15s}
EOF
    fi

    cat >> "${CONFIG_DIR}/.env" <<EOF

# ==================== LOGGING ====================
LOG_LEVEL=${CONFIG_VALUES[LOG_LEVEL]:-INFO}
LOG_FORMAT=${CONFIG_VALUES[LOG_FORMAT]:-json}

# ==================== NETWORK ====================
DOCKER_NETWORK=${CONFIG_VALUES[DOCKER_NETWORK]}
NETWORK_SUBNET=${CONFIG_VALUES[NETWORK_SUBNET]}

# ==================== STORAGE ====================
DATA_DIR=${CONFIG_VALUES[DATA_DIR]}

# ==================== EXTERNAL APIS ====================
EOF

    for api_key in OPENAI_API_KEY ANTHROPIC_API_KEY GOOGLE_AI_API_KEY HUGGINGFACE_API_KEY; do
        if [[ -n "${CONFIG_VALUES[$api_key]:-}" ]]; then
            echo "${api_key}=${CONFIG_VALUES[$api_key]}" >> "${CONFIG_DIR}/.env"
        fi
    done

    if [[ -n "${CONFIG_VALUES[CUSTOM_ENV_VARS]:-}" ]]; then
        cat >> "${CONFIG_DIR}/.env" <<EOF

# ==================== CUSTOM ====================
${CONFIG_VALUES[CUSTOM_ENV_VARS]}
EOF
    fi

    log_success ".env file generated"
}
generate_docker_compose() {
    log_info "Generating docker-compose.yml..."
    
    cat > "${PROJECT_ROOT}/docker-compose.yml" <<'EOF'
version: '3.8'

networks:
  aiplatform:
    driver: bridge
    ipam:
      config:
        - subnet: ${NETWORK_SUBNET:-172.28.0.0/16}

volumes:
  ollama_data:
  webui_data:
  n8n_data:
  postgres_data:
  redis_data:
  prometheus_data:
  grafana_data:
  nginx_conf:
  nginx_ssl:

services:
EOF

    # Ollama Service
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        cat >> "${PROJECT_ROOT}/docker-compose.yml" <<'EOF'

  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    ports:
      - "${OLLAMA_PORT:-11434}:11434"
    volumes:
      - ollama_data:/root/.ollama
    environment:
      - OLLAMA_HOST=${OLLAMA_HOST:-0.0.0.0:11434}
      - OLLAMA_NUM_PARALLEL=${OLLAMA_NUM_PARALLEL:-1}
      - OLLAMA_MAX_LOADED_MODELS=${OLLAMA_MAX_LOADED_MODELS:-1}
      - OLLAMA_KEEP_ALIVE=${OLLAMA_KEEP_ALIVE:-5m}
      - OLLAMA_NUM_CTX=${OLLAMA_NUM_CTX:-2048}
      - OLLAMA_NUM_THREAD=${OLLAMA_NUM_THREAD:-4}
EOF

        if [[ "${CONFIG_VALUES[OLLAMA_GPU_ENABLED]}" == "true" && "${CONFIG_VALUES[OLLAMA_GPU_TYPE]}" == "nvidia" ]]; then
            cat >> "${PROJECT_ROOT}/docker-compose.yml" <<'EOF'
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
EOF
        fi

        cat >> "${PROJECT_ROOT}/docker-compose.yml" <<'EOF'
    networks:
      - aiplatform
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/tags"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF
    fi

    # PostgreSQL Service
    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
        cat >> "${PROJECT_ROOT}/docker-compose.yml" <<'EOF'

  postgres:
    image: postgres:16-alpine
    container_name: postgres
    restart: unless-stopped
    ports:
      - "${POSTGRES_PORT:-5432}:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./config/postgres/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    environment:
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_MAX_CONNECTIONS=${POSTGRES_MAX_CONNECTIONS:-100}
      - POSTGRES_SHARED_BUFFERS=${POSTGRES_SHARED_BUFFERS:-256MB}
    networks:
      - aiplatform
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
EOF
    fi

    # Redis Service
    if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
        cat >> "${PROJECT_ROOT}/docker-compose.yml" <<'EOF'

  redis:
    image: redis:7-alpine
    container_name: redis
    restart: unless-stopped
    ports:
      - "${REDIS_PORT:-6379}:6379"
    volumes:
      - redis_data:/data
      - ./config/redis/redis.conf:/usr/local/etc/redis/redis.conf:ro
    command: redis-server /usr/local/etc/redis/redis.conf
    networks:
      - aiplatform
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
EOF
    fi

    # Open WebUI Service
    if [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]]; then
        cat >> "${PROJECT_ROOT}/docker-compose.yml" <<'EOF'

  webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: unless-stopped
    ports:
      - "${WEBUI_PORT:-3000}:8080"
    volumes:
      - webui_data:/app/backend/data
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}
      - WEBUI_AUTH=${WEBUI_AUTH_METHOD:-local}
      - ENABLE_SIGNUP=${WEBUI_SIGNUP_ENABLED:-true}
EOF

        if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
            cat >> "${PROJECT_ROOT}/docker-compose.yml" <<'EOF'
      - DATABASE_URL=${DATABASE_URL}
EOF
        fi

        if [[ "${CONFIG_VALUES[ENABLE_OAUTH]}" == "true" ]]; then
            cat >> "${PROJECT_ROOT}/docker-compose.yml" <<'EOF'
      - OAUTH_CLIENT_ID=${OAUTH_CLIENT_ID}
      - OAUTH_CLIENT_SECRET=${OAUTH_CLIENT_SECRET}
      - OAUTH_PROVIDER=${OAUTH_PROVIDER}
EOF
            if [[ "${CONFIG_VALUES[OAUTH_PROVIDER]}" == "oidc" ]]; then
                echo "      - OAUTH_ISSUER_URL=\${OAUTH_ISSUER_URL}" >> "${PROJECT_ROOT}/docker-compose.yml"
            fi
        fi

        cat >> "${PROJECT_ROOT}/docker-compose.yml" <<'EOF'
    networks:
      - aiplatform
    depends_on:
      ollama:
        condition: service_healthy
EOF

        if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
            cat >> "${PROJECT_ROOT}/docker-compose.yml" <<'EOF'
      postgres:
        condition: service_healthy
EOF
        fi

        cat >> "${PROJECT_ROOT}/docker-compose.yml" <<'EOF'
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 45s
EOF
    fi

    # n8n Service
    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        cat >> "${PROJECT_ROOT}/docker-compose.yml" <<'EOF'

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "${N8N_PORT:-5678}:5678"
    volumes:
      - n8n_data:/home/node/.n8n
    environment:
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_HOST=${N8N_HOST:-localhost}
      - N8N_PORT=5678
      - N8N_PROTOCOL=${N8N_PROTOCOL:-http}
      - WEBHOOK_URL=${N8N_PROTOCOL}://${N8N_HOST}
EOF

        if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
            cat >> "${PROJECT_ROOT}/docker-compose.yml" <<'EOF'
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
EOF
        fi

        if [[ "${CONFIG_VALUES[N8N_BASIC_AUTH_ACTIVE]}" == "true" ]]; then
            cat >> "${PROJECT_ROOT}/docker-compose.yml" <<'EOF'
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}
EOF
        fi

        cat >> "${PROJECT_ROOT}/docker-compose.yml" <<'EOF'
    networks:
      - aiplatform
EOF

        if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
            cat >> "${PROJECT_ROOT}/docker-compose.yml" <<'EOF'
    depends_on:
      postgres:
        condition: service_healthy
EOF
        fi

        cat >> "${PROJECT_ROOT}/docker-compose.yml" <<'EOF'
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
EOF
    fi

    # Nginx Service
    if [[ "${CONFIG_VALUES[INSTALL_NGINX]}" == "true" ]]; then
        cat >> "${PROJECT_ROOT}/docker-compose.yml" <<'EOF'

  nginx:
    image: nginx:alpine
    container_name: nginx
    restart: unless-stopped
    ports:
      - "${NGINX_HTTP_PORT:-80}:80"
      - "${NGINX_HTTPS_PORT:-443}:443"
    volumes:
      - ./config/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./config/nginx/conf.d:/etc/nginx/conf.d:ro
      - nginx_ssl:/etc/nginx/ssl
      - ./logs/nginx:/var/log/nginx
    networks:
      - aiplatform
    depends_on:
EOF

        [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]] && echo "      - ollama" >> "${PROJECT_ROOT}/docker-compose.yml"
        [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]] && echo "      - webui" >> "${PROJECT_ROOT}/docker-compose.yml"
        [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]] && echo "      - n8n" >> "${PROJECT_ROOT}/docker-compose.yml"

        cat >> "${PROJECT_ROOT}/docker-compose.yml" <<'EOF'
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF
    fi

    # Monitoring Services
    if [[ "${CONFIG_VALUES[INSTALL_MONITORING]}" == "true" ]]; then
        cat >> "${PROJECT_ROOT}/docker-compose.yml" <<'EOF'

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    ports:
      - "${PROMETHEUS_PORT:-9090}:9090"
    volumes:
      - ./config/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./config/prometheus/alerts:/etc/prometheus/alerts:ro
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=${PROMETHEUS_RETENTION:-15d}'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
    networks:
      - aiplatform
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 10s
      retries: 3

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    ports:
      - "${GRAFANA_PORT:-3001}:3000"
    volumes:
      - grafana_data:/var/lib/grafana
      - ./config/grafana/provisioning:/etc/grafana/provisioning:ro
      - ./config/grafana/dashboards:/var/lib/grafana/dashboards:ro
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER:-admin}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
      - GF_INSTALL_PLUGINS=
      - GF_SERVER_ROOT_URL=http://localhost:${GRAFANA_PORT:-3001}
    networks:
      - aiplatform
    depends_on:
      - prometheus
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "9100:9100"
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    networks:
      - aiplatform

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    privileged: true
    devices:
      - /dev/kmsg
    networks:
      - aiplatform
EOF

        if [[ "${CONFIG_VALUES[ENABLE_ALERTING]}" == "true" ]]; then
            cat >> "${PROJECT_ROOT}/docker-compose.yml" <<'EOF'

  alertmanager:
    image: prom/alertmanager:latest
    container_name: alertmanager
    restart: unless-stopped
    ports:
      - "9093:9093"
    volumes:
      - ./config/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
      - '--storage.path=/alertmanager'
    networks:
      - aiplatform
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:9093/-/healthy"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF
        fi
    fi

    log_success "docker-compose.yml generated"
}

generate_nginx_config() {
    if [[ "${CONFIG_VALUES[INSTALL_NGINX]}" != "true" ]]; then
        return
    fi
    
    log_info "Generating Nginx configuration..."
    
    mkdir -p "${CONFIG_DIR}/nginx/conf.d"
    
    # Main nginx.conf
    cat > "${CONFIG_DIR}/nginx/nginx.conf" <<'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size ${CLIENT_MAX_BODY_SIZE:-100m};

    gzip on;
    gzip_vary on;
    gzip_min_length 1000;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    include /etc/nginx/conf.d/*.conf;
}
EOF

    # Health check endpoint
    cat > "${CONFIG_DIR}/nginx/conf.d/health.conf" <<'EOF'
server {
    listen 80;
    server_name _;

    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

    # WebUI configuration
    if [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]]; then
        local webui_server_name="${CONFIG_VALUES[WEBUI_DOMAIN]:-_}"
        
        cat > "${CONFIG_DIR}/nginx/conf.d/webui.conf" <<EOF
server {
    listen 80;
    server_name ${webui_server_name};

    location / {
        proxy_pass http://webui:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF

        if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/nginx/conf.d/webui.conf" <<EOF

server {
    listen 443 ssl http2;
    server_name ${webui_server_name};

    ssl_certificate /etc/nginx/ssl/${webui_server_name}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/${webui_server_name}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass http://webui:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
        fi
    fi

    # n8n configuration
    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        local n8n_server_name="${CONFIG_VALUES[N8N_DOMAIN]:-_}"
        
        cat > "${CONFIG_DIR}/nginx/conf.d/n8n.conf" <<EOF
server {
    listen 80;
    server_name ${n8n_server_name};

    location / {
        proxy_pass http://n8n:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        chunked_transfer_encoding off;
        proxy_buffering off;
        proxy_cache off;
    }
}
EOF

        if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/nginx/conf.d/n8n.conf" <<EOF

server {
    listen 443 ssl http2;
    server_name ${n8n_server_name};

    ssl_certificate /etc/nginx/ssl/${n8n_server_name}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/${n8n_server_name}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass http://n8n:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
        fi
    fi

    log_success "Nginx configuration generated"
}

generate_prometheus_config() {
    if [[ "${CONFIG_VALUES[INSTALL_MONITORING]}" != "true" ]]; then
        return
    fi
    
    log_info "Generating Prometheus configuration..."
    
    mkdir -p "${CONFIG_DIR}/prometheus/alerts"
    
    cat > "${CONFIG_DIR}/prometheus/prometheus.yml" <<EOF
global:
  scrape_interval: ${CONFIG_VALUES[PROMETHEUS_SCRAPE_INTERVAL]:-15s}
  evaluation_interval: 15s
  external_labels:
    cluster: 'aiplatform'
    environment: '${CONFIG_VALUES[ENVIRONMENT]}'

alerting:
EOF

    if [[ "${CONFIG_VALUES[ENABLE_ALERTING]}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" <<'EOF'
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093
EOF
    fi

    cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" <<'EOF'

rule_files:
  - '/etc/prometheus/alerts/*.yml'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
EOF

    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" <<'EOF'

  - job_name: 'ollama'
    static_configs:
      - targets: ['ollama:11434']
EOF
    fi

    # Alert rules
    if [[ "${CONFIG_VALUES[ENABLE_ALERTING]}" == "true" ]]; then
        cat > "${CONFIG_DIR}/prometheus/alerts/general.yml" <<EOF
groups:
  - name: general
    interval: 30s
    rules:
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > ${CONFIG_VALUES[ALERT_CPU_THRESHOLD]:-80}
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"
          description: "CPU usage is above ${CONFIG_VALUES[ALERT_CPU_THRESHOLD]:-80}% (current: {{ \$value }}%)"

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > ${CONFIG_VALUES[ALERT_MEMORY_THRESHOLD]:-85}
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage detected"
          description: "Memory usage is above ${CONFIG_VALUES[ALERT_MEMORY_THRESHOLD]:-85}% (current: {{ \$value }}%)"

      - alert: HighDiskUsage
        expr: (1 - (node_filesystem_avail_bytes{fstype!~"tmpfs|fuse.lxcfs"} / node_filesystem_size_bytes)) * 100 > ${CONFIG_VALUES[ALERT_DISK_THRESHOLD]:-90}
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High disk usage detected"
          description: "Disk usage is above ${CONFIG_VALUES[ALERT_DISK_THRESHOLD]:-90}% (current: {{ \$value }}%)"

      - alert: ServiceDown
        expr: up == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Service {{ \$labels.job }} is down"
          description: "{{ \$labels.instance }} of job {{ \$labels.job }} has been down for more than 2 minutes"
EOF
    fi

    log_success "Prometheus configuration generated"
}

generate_grafana_config() {
    if [[ "${CONFIG_VALUES[INSTALL_MONITORING]}" != "true" ]]; then
        return
    fi
    
    log_info "Generating Grafana configuration..."
    
    mkdir -p "${CONFIG_DIR}/grafana/provisioning/datasources"
    mkdir -p "${CONFIG_DIR}/grafana/provisioning/dashboards"
    mkdir -p "${CONFIG_DIR}/grafana/dashboards"
    
    # Datasource configuration
    cat > "${CONFIG_DIR}/grafana/provisioning/datasources/prometheus.yml" <<'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
    jsonData:
      timeInterval: 15s
EOF

    # Dashboard provisioning
    cat > "${CONFIG_DIR}/grafana/provisioning/dashboards/default.yml" <<'EOF'
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF

    log_success "Grafana configuration generated"
}

generate_redis_config() {
    if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" != "true" ]]; then
        return
    fi
    
    log_info "Generating Redis configuration..."
    
    mkdir -p "${CONFIG_DIR}/redis"
    
    cat > "${CONFIG_DIR}/redis/redis.conf" <<EOF
# Redis Configuration
bind 0.0.0.0
protected-mode yes
port 6379
tcp-backlog 511
timeout 0
tcp-keepalive 300

daemonize no
supervised no
pidfile /var/run/redis_6379.pid
loglevel notice
logfile ""

databases 16
always-show-logo yes

save 900 1
save 300 10
save 60 10000

stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /data

maxmemory ${CONFIG_VALUES[REDIS_MAX_MEMORY]:-256}mb
maxmemory-policy ${CONFIG_VALUES[REDIS_EVICTION_POLICY]:-allkeys-lru}

appendonly no
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
EOF

    log_success "Redis configuration generated"
}

generate_postgres_init() {
    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" != "true" ]]; then
        return
    fi
    
    log_info "Generating PostgreSQL initialization script..."
    
    mkdir -p "${CONFIG_DIR}/postgres"
    
    cat > "${CONFIG_DIR}/postgres/init.sql" <<EOF
-- AI Platform Database Initialization
-- Generated: $(date)

-- Create extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create schemas if needed
CREATE SCHEMA IF NOT EXISTS public;

-- Grant permissions
GRANT ALL ON SCHEMA public TO ${CONFIG_VALUES[POSTGRES_USER]};

-- Create initial tables (customize as needed)
CREATE TABLE IF NOT EXISTS system_info (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    key VARCHAR(255) UNIQUE NOT NULL,
    value TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert system metadata
INSERT INTO system_info (key, value) VALUES 
    ('version', '${VERSION}'),
    ('installed_at', NOW()::TEXT),
    ('environment', '${CONFIG_VALUES[ENVIRONMENT]}')
ON CONFLICT (key) DO NOTHING;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_system_info_key ON system_info(key);

COMMENT ON TABLE system_info IS 'System configuration and metadata';
EOF

    log_success "PostgreSQL initialization script generated"
}

generate_alertmanager_config() {
    if [[ "${CONFIG_VALUES[INSTALL_MONITORING]}" != "true" || "${CONFIG_VALUES[ENABLE_ALERTING]}" != "true" ]]; then
        return
    fi
    
    log_info "Generating Alertmanager configuration..."
    
    mkdir -p "${CONFIG_DIR}/alertmanager"
    
    cat > "${CONFIG_DIR}/alertmanager/alertmanager.yml" <<EOF
global:
  resolve_timeout: 5m
EOF

    case "${CONFIG_VALUES[ALERT_METHOD]}" in
        email)
            cat >> "${CONFIG_DIR}/alertmanager/alertmanager.yml" <<EOF
  smtp_from: '${CONFIG_VALUES[ALERT_EMAIL_FROM]}'
  smtp_smarthost: '${CONFIG_VALUES[SMTP_HOST]}:${CONFIG_VALUES[SMTP_PORT]}'
  smtp_auth_username: '${CONFIG_VALUES[SMTP_USER]}'
  smtp_auth_password: '${CONFIG_VALUES[SMTP_PASSWORD]}'
  smtp_require_tls: true
EOF
            ;;
    esac

    cat >> "${CONFIG_DIR}/alertmanager/alertmanager.yml" <<'EOF'

route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'default'

receivers:
  - name: 'default'
EOF

    case "${CONFIG_VALUES[ALERT_METHOD]}" in
        email)
            cat >> "${CONFIG_DIR}/alertmanager/alertmanager.yml" <<EOF
    email_configs:
      - to: '${CONFIG_VALUES[ALERT_EMAIL_TO]}'
        headers:
          Subject: '[AI Platform Alert] {{ .GroupLabels.alertname }}'
EOF
            ;;
        slack)
            cat >> "${CONFIG_DIR}/alertmanager/alertmanager.yml" <<EOF
    slack_configs:
      - api_url: '${CONFIG_VALUES[SLACK_WEBHOOK_URL]}'
        channel: '${CONFIG_VALUES[SLACK_CHANNEL]}'
        title: '[AI Platform Alert] {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
EOF
            ;;
        discord)
            cat >> "${CONFIG_DIR}/alertmanager/alertmanager.yml" <<EOF
    webhook_configs:
      - url: '${CONFIG_VALUES[DISCORD_WEBHOOK_URL]}'
EOF
            ;;
        webhook)
            cat >> "${CONFIG_DIR}/alertmanager/alertmanager.yml" <<EOF
    webhook_configs:
      - url: '${CONFIG_VALUES[ALERT_WEBHOOK_URL]}'
EOF
            ;;
    esac

    cat >> "${CONFIG_DIR}/alertmanager/alertmanager.yml" <<'EOF'

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'cluster', 'service']
EOF

    log_success "Alertmanager configuration generated"
}

################################################################################
# DEPLOYMENT FUNCTIONS
################################################################################

pull_docker_images() {
    log_info "Pulling Docker images..."
    
    cd "$PROJECT_ROOT"
    docker-compose pull || {
        log_error "Failed to pull Docker images"
        return 1
    }
    
    log_success "Docker images pulled successfully"
}

create_directories() {
    log_info "Creating directory structure..."
    
    local dirs=(
        "${CONFIG_VALUES[DATA_DIR]}"
        "${CONFIG_DIR}"
        "${LOG_DIR}"
        "${BACKUP_DIR}"
        "${CONFIG_DIR}/nginx/conf.d"
        "${CONFIG_DIR}/prometheus/alerts"
        "${CONFIG_DIR}/grafana/provisioning"
        "${CONFIG_DIR}/redis"
        "${CONFIG_DIR}/postgres"
        "${CONFIG_DIR}/alertmanager"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        log_info "Created directory: $dir"
    done
    
    log_success "Directories created"
}

set_permissions() {
    log_info "Setting permissions..."
    
    # Set ownership for data directories
    if [[ -d "${CONFIG_VALUES[DATA_DIR]}" ]]; then
        sudo chown -R 1000:1000 "${CONFIG_VALUES[DATA_DIR]}" || true
    fi
    
    # Set permissions for config files
    chmod 600 "${CONFIG_DIR}/.env" 2>/dev/null || true
    chmod 644 "${CONFIG_DIR}"/*.conf 2>/dev/null || true
    
    log_success "Permissions set"
}

configure_firewall() {
    if [[ "${CONFIG_VALUES[ENABLE_FIREWALL]}" != "true" ]]; then
        return
    fi
    
    log_info "Configuring UFW firewall..."
    
    if ! command_exists ufw; then
        log_warning "UFW not installed, skipping firewall configuration"
        return
    fi
    
    # Enable UFW
    sudo ufw --force enable
    
    # Allow SSH
    sudo ufw allow 22/tcp
    
    # Allow configured ports
    [[ -n "${CONFIG_VALUES[NGINX_HTTP_PORT]:-}" ]] && sudo ufw allow "${CONFIG_VALUES[NGINX_HTTP_PORT]}/tcp"
    [[ -n "${CONFIG_VALUES[NGINX_HTTPS_PORT]:-}" ]] && sudo ufw allow "${CONFIG_VALUES[NGINX_HTTPS_PORT]}/tcp"
    
    # Allow monitoring ports (restricted to localhost in production)
    if [[ "${CONFIG_VALUES[ENVIRONMENT]}" == "development" ]]; then
        [[ -n "${CONFIG_VALUES[PROMETHEUS_PORT]:-}" ]] && sudo ufw allow "${CONFIG_VALUES[PROMETHEUS_PORT]}/tcp"
        [[ -n "${CONFIG_VALUES[GRAFANA_PORT]:-}" ]] && sudo ufw allow "${CONFIG_VALUES[GRAFANA_PORT]}/tcp"
    fi
    
    sudo ufw reload
    
    log_success "Firewall configured"
}

start_services() {
    log_info "Starting services..."
    
    cd "$PROJECT_ROOT"
    
    # Start services
    if ! docker-compose up -d; then
        log_error "Failed to start services"
        return 1
    fi
    
    log_success "Services started"
    
    # Wait for services to be healthy
    log_info "Waiting for services to be healthy..."
    sleep 10
    
    local max_wait=120
    local waited=0
    
    while [[ $waited -lt $max_wait ]]; do
        if docker-compose ps | grep -q "unhealthy"; then
            log_warning "Some services are still starting... ($waited/$max_wait seconds)"
            sleep 10
            ((waited+=10))
        else
            break
        fi
    done
    
    # Show service status
    docker-compose ps
}

download_ollama_models() {
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" != "true" || -z "${CONFIG_VALUES[OLLAMA_MODELS]:-}" ]]; then
        return
    fi
    
    log_info "Downloading Ollama models..."
    
    IFS=',' read -ra models <<< "${CONFIG_VALUES[OLLAMA_MODELS]}"
    
    for model in "${models[@]}"; do
        model=$(echo "$model" | tr -d ' ')
        log_info "Pulling model: $model"
        
        docker exec ollama ollama pull "$model" || {
            log_warning "Failed to pull model: $model"
            continue
        }
        
        log_success "Model pulled: $model"
    done
    
    log_success "All models downloaded"
}

setup_ssl_certificates() {
    if [[ "${CONFIG_VALUES[ENABLE_SSL]}" != "true" || "${CONFIG_VALUES[SSL_METHOD]}" != "letsencrypt" ]]; then
        return
    fi
    
    log_info "Setting up SSL certificates with Let's Encrypt..."
    
    if ! command_exists certbot; then
        log_info "Installing certbot..."
        sudo apt-get update
        sudo apt-get install -y certbot python3-certbot-nginx
    fi
    
    local domains=()
    [[ -n "${CONFIG_VALUES[WEBUI_DOMAIN]:-}" && "${CONFIG_VALUES[WEBUI_DOMAIN]}" != "_" ]] && domains+=("${CONFIG_VALUES[WEBUI_DOMAIN]}")
    [[ -n "${CONFIG_VALUES[N8N_DOMAIN]:-}" && "${CONFIG_VALUES[N8N_DOMAIN]}" != "_" ]] && domains+=("${CONFIG_VALUES[N8N_DOMAIN]}")
    
    if [[ ${#domains[@]} -eq 0 ]]; then
        log_warning "No domains configured for SSL certificates"
        return
    fi
    
    for domain in "${domains[@]}"; do
        log_info "Obtaining certificate for: $domain"
        
        sudo certbot certonly --standalone \
            --non-interactive \
            --agree-tos \
            --email "${CONFIG_VALUES[SSL_EMAIL]}" \
            -d "$domain" \
            --pre-hook "docker-compose stop nginx" \
            --post-hook "docker-compose start nginx" || {
            log_warning "Failed to obtain certificate for: $domain"
            continue
        }
        
        # Copy certificates to nginx volume
        sudo mkdir -p "${PROJECT_ROOT}/nginx_ssl/${domain}"
        sudo cp "/etc/letsencrypt/live/${domain}/fullchain.pem" "${PROJECT_ROOT}/nginx_ssl/${domain}/"
        sudo cp "/etc/letsencrypt/live/${domain}/privkey.pem" "${PROJECT_ROOT}/nginx_ssl/${domain}/"
        
        log_success "Certificate obtained for: $domain"
    done
    
    # Setup auto-renewal
    if ! sudo crontab -l 2>/dev/null | grep -q certbot; then
        (sudo crontab -l 2>/dev/null; echo "0 0,12 * * * certbot renew --quiet --post-hook 'cd $PROJECT_ROOT && docker-compose restart nginx'") | sudo crontab -
        log_success "SSL certificate auto-renewal configured"
    fi
}

create_backup_script() {
    if [[ "${CONFIG_VALUES[BACKUP_ENABLED]}" != "true" ]]; then
        return
    fi
    
    log_info "Creating backup script..."
    
    cat > "${PROJECT_ROOT}/scripts/backup.sh" <<'BACKUP_SCRIPT'
#!/bin/bash
set -euo pipefail

BACKUP_DIR="/var/backups/aiplatform"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="aiplatform_${TIMESTAMP}"

mkdir -p "$BACKUP_DIR"

echo "Starting backup: $BACKUP_NAME"

# Backup Docker volumes
docker-compose -f "$(dirname "$0")/../docker-compose.yml" stop

tar -czf "${BACKUP_DIR}/${BACKUP_NAME}_volumes.tar.gz" \
    -C / \
    var/lib/docker/volumes/aiplatform_* 2>/dev/null || true

# Backup configuration
tar -czf "${BACKUP_DIR}/${BACKUP_NAME}_config.tar.gz" \
    -C "$(dirname "$0")/.." \
    config/ .env 2>/dev/null || true

# Backup databases
if docker ps -a | grep -q postgres; then
    docker exec postgres pg_dumpall -U "${POSTGRES_USER:-postgres}" | \
        gzip > "${BACKUP_DIR}/${BACKUP_NAME}_postgres.sql.gz"
fi

docker-compose -f "$(dirname "$0")/../docker-compose.yml" start

echo "Backup completed: ${BACKUP_DIR}/${BACKUP_NAME}_*"

# Cleanup old backups
find "$BACKUP_DIR" -name "aiplatform_*" -mtime +${RETENTION_DAYS:-7} -delete

echo "Old backups cleaned up"
BACKUP_SCRIPT

    chmod +x "${PROJECT_ROOT}/scripts/backup.sh"
    
    # Setup backup cron job
    if [[ -n "${CONFIG_VALUES[BACKUP_SCHEDULE]:-}" ]]; then
        (crontab -l 2>/dev/null | grep -v "aiplatform.*backup"; \
         echo "${CONFIG_VALUES[BACKUP_SCHEDULE]} ${PROJECT_ROOT}/scripts/backup.sh >> ${LOG_DIR}/backup.log 2>&1") | crontab -
        log_success "Backup cron job configured"
    fi
    
    log_success "Backup script created"
}

create_helper_scripts() {
    log_info "Creating helper scripts..."
    
    mkdir -p "${PROJECT_ROOT}/scripts"
    
    # Start script
    cat > "${PROJECT_ROOT}/scripts/start.sh" <<'EOF'
#!/bin/bash
cd "$(dirname "$0")/.."
docker-compose up -d
docker-compose ps
EOF

    # Stop script
    cat > "${PROJECT_ROOT}/scripts/stop.sh" <<'EOF'
#!/bin/bash
cd "$(dirname "$0")/.."
docker-compose down
EOF

    # Restart script
    cat > "${PROJECT_ROOT}/scripts/restart.sh" <<'EOF'
#!/bin/bash
cd "$(dirname "$0")/.."
docker-compose restart
docker-compose ps
EOF

    # Logs script
    cat > "${PROJECT_ROOT}/scripts/logs.sh" <<'EOF'
#!/bin/bash
cd "$(dirname "$0")/.."
docker-compose logs -f "$@"
EOF

    # Status script
    cat > "${PROJECT_ROOT}/scripts/status.sh" <<'EOF'
#!/bin/bash
cd "$(dirname "$0")/.."
echo "=== Service Status ==="
docker-compose ps
echo
echo "=== Resource Usage ==="
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
EOF

    # Update script
    cat > "${PROJECT_ROOT}/scripts/update.sh" <<'EOF'
#!/bin/bash
set -e
cd "$(dirname "$0")/.."
echo "Pulling latest images..."
docker-compose pull
echo "Restarting services..."
docker-compose up -d
echo "Update complete!"
docker-compose ps
EOF

    chmod +x "${PROJECT_ROOT}"/scripts/*.sh
    
    log_success "Helper scripts created"
}

display_success_message() {
    echo
    echo "=========================================="
    echo -e "${GREEN}${BOLD}Installation Complete!${NC}"
    echo "=========================================="
    echo
    echo "Services are running:"
    echo
    
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        echo -e "${CYAN}Ollama:${NC} http://localhost:${CONFIG_VALUES[OLLAMA_PORT]}"
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]]; then
        local webui_url="http://localhost:${CONFIG_VALUES[WEBUI_PORT]}"
        [[ -n "${CONFIG_VALUES[WEBUI_DOMAIN]:-}" && "${CONFIG_VALUES[WEBUI_DOMAIN]}" != "_" ]] && webui_url="http://${CONFIG_VALUES[WEBUI_DOMAIN]}"
        echo -e "${CYAN}Open WebUI:${NC} $webui_url"
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        local n8n_url="http://localhost:${CONFIG_VALUES[N8N_PORT]}"
        [[ -n "${CONFIG_VALUES[N8N_DOMAIN]:-}" && "${CONFIG_VALUES[N8N_DOMAIN]}" != "_" ]] && n8n_url="http://${CONFIG_VALUES[N8N_DOMAIN]}"
        echo -e "${CYAN}n8n:${NC} $n8n_url"
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_MONITORING]}" == "true" ]]; then
        echo -e "${CYAN}Prometheus:${NC} http://localhost:${CONFIG_VALUES[PROMETHEUS_PORT]}"
        echo -e "${CYAN}Grafana:${NC} http://localhost:${CONFIG_VALUES[GRAFANA_PORT]}"
        echo -e "  ${YELLOW}Username:${NC} ${CONFIG_VALUES[GRAFANA_ADMIN_USER]}"
        echo -e "  ${YELLOW}Password:${NC} ${CONFIG_VALUES[GRAFANA_ADMIN_PASSWORD]}"
    fi
    
    echo
    echo "Useful commands:"
    echo -e "  ${CYAN}Start services:${NC} ./scripts/start.sh"
    echo -e "  ${CYAN}Stop services:${NC} ./scripts/stop.sh"
    echo -e "  ${CYAN}View logs:${NC} ./scripts/logs.sh"
    echo -e "  ${CYAN}Check status:${NC} ./scripts/status.sh"
    
    if [[ "${CONFIG_VALUES[BACKUP_ENABLED]}" == "true" ]]; then
        echo -e "  ${CYAN}Manual backup:${NC} ./scripts/backup.sh"
    fi
    
    echo
    echo "Configuration saved to: ${CONFIG_DIR}"
    echo "Logs available at: ${LOG_DIR}"
    echo
    echo "=========================================="
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    print_header
    
    # Initialize
    create_directories
    
    # System checks
    check_os
    check_system_requirements
    
    # Docker setup
    if ! command_exists docker; then
        if prompt_yes_no "Docker not found. Install Docker?" "y"; then
            install_docker
        else
            log_error "Docker is required"
            exit 1
        fi
    fi
    
    check_docker_compose
    
    # Configuration wizard
    log_info "Starting configuration wizard..."
    echo
    
    step_01_welcome
    step_02_environment
    step_03_services
    step_04_ports
    step_05_storage_config
    step_06_database_config
    step_07_proxy_config
    step_08_backup_config
    step_09_logging_config
    step_10_resource_config
    step_11_network_config
    step_12_timezone_config
    step_13_auth_config
    step_14_model_selection
    step_15_model_settings
    step_16_monitoring_config
    step_17_email_config
    step_18_security_config
    step_19_performance_config
    step_20_update_config
    step_21_development_config
    step_22_webhook_config
    step_23_api_keys
    step_24_custom_env
    step_25_experimental_features
    step_26_review_config
    step_27_save_config
    
    # Generate configuration files
    log_info "Generating configuration files..."
    generate_env_file
    generate_docker_compose
    generate_nginx_config
    generate_prometheus_config
    generate_grafana_config
    generate_redis_config
    generate_postgres_init
    generate_alertmanager_config
    
    # Deploy
    log_info "Deploying services..."
    pull_docker_images
    set_permissions
    configure_firewall
    start_services
    
    # Post-deployment
    download_ollama_models
    setup_ssl_certificates
    create_backup_script
    create_helper_scripts
    
    # Finish
    display_success_message
    
    log_success "Setup completed successfully!"
}

# Run main function
main "$@"
