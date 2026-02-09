#!/bin/bash
################################################################################
# AI Platform System Setup Script
# Version: 1.0.0
# Description: Interactive installation wizard for AI platform stack
################################################################################

set -euo pipefail
IFS= $ '\n\t'

################################################################################
# CONSTANTS AND GLOBALS
################################################################################

readonly SCRIPT_DIR=" $ (cd " $ (dirname " $ {BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT=" $ (dirname " $ SCRIPT_DIR")"
readonly CONFIG_DIR="${PROJECT_ROOT}/config"
readonly LOG_DIR="${PROJECT_ROOT}/logs"
readonly BACKUP_DIR="${PROJECT_ROOT}/backups"
readonly TIMESTAMP= $ (date +%Y%m%d_%H%M%S)
readonly LOG_FILE=" $ {LOG_DIR}/setup_${TIMESTAMP}.log"

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
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# Configuration storage
declare -A CONFIG_VALUES

################################################################################
# LOGGING FUNCTIONS
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC}  $ *" | tee -a " $ LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC}  $ *" | tee -a " $ LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC}  $ *" | tee -a " $ LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC}  $ *" | tee -a " $ LOG_FILE"
}

log_step() {
    echo -e "\n${CYAN}${BOLD}═══  $ * ═══ $ {NC}\n" | tee -a " $ LOG_FILE"
}

################################################################################
# UTILITY FUNCTIONS
################################################################################

prompt_yes_no() {
    local prompt=" $ 1"
    local default="${2:-n}"
    local response
    
    while true; do
        if [[ " $ default" == "y" ]]; then
            read -rp " $ prompt [Y/n]: " response
            response=${response:-y}
        else
            read -rp " $ prompt [y/N]: " response
            response= $ {response:-n}
        fi
        
        case " $ response" in
            [yY][eE][sS]|[yY]) return 0 ;;
            [nN][oO]|[nN]) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

prompt_input() {
    local prompt=" $ 1"
    local default=" $ 2"
    local response
    
    if [[ -n " $ default" ]]; then
        read -rp " $ prompt [ $ default]: " response
        echo "${response:- $ default}"
    else
        read -rp " $ prompt: " response
        echo " $ response"
    fi
}

prompt_password() {
    local prompt=" $ 1"
    local password
    local password_confirm
    
    while true; do
        read -rsp " $ prompt: " password
        echo
        read -rsp "Confirm password: " password_confirm
        echo
        
        if [[ " $ password" == " $ password_confirm" ]]; then
            echo " $ password"
            return 0
        else
            log_error "Passwords do not match. Please try again."
        fi
    done
}

prompt_select() {
    local prompt=" $ 1"
    shift
    local options=(" $ @")
    local choice
    
    echo " $ prompt"
    for i in " $ {!options[@]}"; do
        echo "  $((i + 1)). ${options[ $ i]}"
    done
    
    while true; do
        read -rp "Enter choice [1- $ {#options[@]}]: " choice
        if [[ " $ choice" =~ ^[0-9]+ $  ]] && ((choice >= 1 && choice <= ${#options[@]})); then
            echo "${options[$((choice - 1))]}"
            return 0
        else
            log_error "Invalid choice. Please enter a number between 1 and ${#options[@]}."
        fi
    done
}

generate_random_string() {
    local length="${1:-32}"
    openssl rand -base64 48 | tr -d "=+/" | cut -c1-" $ length"
}

validate_port() {
    local port=" $ 1"
    if [[ " $ port" =~ ^[0-9]+ $  ]] && ((port >= 1024 && port <= 65535)); then
        return 0
    else
        return 1
    fi
}

validate_domain() {
    local domain=" $ 1"
    if [[ " $ domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

check_port_available() {
    local port=" $ 1"
    if netstat -tuln 2>/dev/null | grep -q ": $ port "; then
        return 1
    else
        return 0
    fi
}

################################################################################
# PREREQUISITE CHECKS
################################################################################

check_system_requirements() {
    log_step "Checking System Requirements"
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root"
        exit 1
    fi
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        log_error "Unable to determine operating system"
        exit 1
    fi
    
    source /etc/os-release
    log_info "Operating System:  $ PRETTY_NAME"
    
    # Check architecture
    local arch= $ (uname -m)
    log_info "Architecture:  $ arch"
    
    if [[ " $ arch" != "x86_64" ]] && [[ "$arch" != "aarch64" ]]; then
        log_warn "Unsupported architecture:  $ arch"
    fi
    
    # Check available disk space (minimum 20GB)
    local available_space= $ (df -BG "$PROJECT_ROOT" | awk 'NR==2 {print $4}' | sed 's/G//')
    log_info "Available disk space: ${available_space}GB"
    
    if ((available_space < 20)); then
        log_warn "Low disk space. At least 20GB recommended."
        if ! prompt_yes_no "Continue anyway?" "n"; then
            exit 1
        fi
    fi
    
    # Check memory
    local total_mem=$(free -g | awk '/^Mem:/{print $2}')
    log_info "Total memory: ${total_mem}GB"
    
    if ((total_mem < 4)); then
        log_warn "Low memory. At least 4GB recommended for optimal performance."
    fi
    
    log_success "System requirements check complete"
}

check_docker() {
    log_step "Checking Docker Installation"
    
    if ! command -v docker &> /dev/null; then
        log_warn "Docker not found"
        return 1
    fi
    
    # Check Docker version
    local docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "0.0.0")
    log_info "Docker version:  $ docker_version"
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        return 1
    fi
    
    # Check Docker Compose
    if docker compose version &> /dev/null; then
        local compose_version= $ (docker compose version --short)
        log_info "Docker Compose version:  $ compose_version"
    else
        log_warn "Docker Compose plugin not found"
        return 1
    fi
    
    # Check Docker permissions
    if ! docker ps &> /dev/null; then
        log_warn "Current user cannot access Docker. May need to add user to docker group."
        return 1
    fi
    
    log_success "Docker check complete"
    return 0
}

install_docker() {
    log_step "Installing Docker"
    
    if ! prompt_yes_no "Install Docker now?" "y"; then
        log_error "Docker is required. Installation cancelled."
        exit 1
    fi
    
    log_info "Downloading Docker installation script..."
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    
    log_info "Installing Docker..."
    sudo sh /tmp/get-docker.sh
    
    log_info "Adding current user to docker group..."
    sudo usermod -aG docker " $ USER"
    
    rm /tmp/get-docker.sh
    
    log_success "Docker installed successfully"
    log_warn "You may need to log out and back in for group changes to take effect"
    
    if prompt_yes_no "Start Docker service now?" "y"; then
        sudo systemctl start docker
        sudo systemctl enable docker
    fi
}

################################################################################
# CONFIGURATION COLLECTION FUNCTIONS
################################################################################

step_01_installation_type() {
    log_step "Step 1/27: Installation Type"
    
    echo "Select installation type:"
    echo "  1. Development - Minimal setup for development/testing"
    echo "  2. Production - Full setup with security and monitoring"
    echo "  3. Custom - Choose components individually"
    echo ""
    
    local install_type= $ (prompt_select "Choose installation type:" "development" "production" "custom")
    
    CONFIG_VALUES[INSTALL_TYPE]=" $ install_type"
    log_info "Installation type:  $ install_type"
}

step_02_project_info() {
    log_step "Step 2/27: Project Information"
    
    local project_name= $ (prompt_input "Enter project name" "aiplatform")
    project_name= $ (echo " $ project_name" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-' | tr -cd '[:alnum:]-')
    
    local environment= $ (prompt_select "Select environment:" "development" "staging" "production")
    
    CONFIG_VALUES[PROJECT_NAME]=" $ project_name"
    CONFIG_VALUES[ENVIRONMENT]=" $ environment"
    CONFIG_VALUES[COMPOSE_PROJECT_NAME]=" $ {project_name}_${environment}"
    
    log_info "Project: $project_name"
    log_info "Environment:  $ environment"
}

step_03_stack_selection() {
    log_step "Step 3/27: Stack Component Selection"
    
    if [[ " $ {CONFIG_VALUES[INSTALL_TYPE]}" == "custom" ]]; then
        CONFIG_VALUES[INSTALL_OLLAMA]= $ (prompt_yes_no "Install Ollama?" "y" && echo "true" || echo "false")
        CONFIG_VALUES[INSTALL_WEBUI]= $ (prompt_yes_no "Install Open WebUI?" "y" && echo "true" || echo "false")
        CONFIG_VALUES[INSTALL_N8N]= $ (prompt_yes_no "Install n8n?" "y" && echo "true" || echo "false")
        CONFIG_VALUES[INSTALL_POSTGRES]= $ (prompt_yes_no "Install PostgreSQL?" "y" && echo "true" || echo "false")
        CONFIG_VALUES[INSTALL_REDIS]= $ (prompt_yes_no "Install Redis?" "y" && echo "true" || echo "false")
        CONFIG_VALUES[INSTALL_NGINX]= $ (prompt_yes_no "Install Nginx reverse proxy?" "y" && echo "true" || echo "false")
        CONFIG_VALUES[INSTALL_MONITORING]= $ (prompt_yes_no "Install monitoring stack (Prometheus/Grafana)?" "n" && echo "true" || echo "false")
    else
        # Default selections based on install type
        if [[ " $ {CONFIG_VALUES[INSTALL_TYPE]}" == "production" ]]; then
            CONFIG_VALUES[INSTALL_OLLAMA]="true"
            CONFIG_VALUES[INSTALL_WEBUI]="true"
            CONFIG_VALUES[INSTALL_N8N]="true"
            CONFIG_VALUES[INSTALL_POSTGRES]="true"
            CONFIG_VALUES[INSTALL_REDIS]="true"
            CONFIG_VALUES[INSTALL_NGINX]="true"
            CONFIG_VALUES[INSTALL_MONITORING]="true"
        else
            CONFIG_VALUES[INSTALL_OLLAMA]="true"
            CONFIG_VALUES[INSTALL_WEBUI]="true"
            CONFIG_VALUES[INSTALL_N8N]="true"
            CONFIG_VALUES[INSTALL_POSTGRES]="true"
            CONFIG_VALUES[INSTALL_REDIS]="false"
            CONFIG_VALUES[INSTALL_NGINX]="false"
            CONFIG_VALUES[INSTALL_MONITORING]="false"
        fi
    fi
    
    log_info "Components to install:"
    [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]] && log_info "  ✓ Ollama"
    [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]] && log_info "  ✓ Open WebUI"
    [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]] && log_info "  ✓ n8n"
    [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]] && log_info "  ✓ PostgreSQL"
    [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]] && log_info "  ✓ Redis"
    [[ "${CONFIG_VALUES[INSTALL_NGINX]}" == "true" ]] && log_info "  ✓ Nginx"
    [[ "${CONFIG_VALUES[INSTALL_MONITORING]}" == "true" ]] && log_info "  ✓ Monitoring"
}

step_04_service_ports() {
    log_step "Step 4/27: Service Port Configuration"
    
    # Ollama ports
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        local ollama_port= $ (prompt_input "Ollama API port" "11434")
        while ! validate_port " $ ollama_port" || ! check_port_available "$ollama_port"; do
            log_error "Port  $ ollama_port is invalid or already in use"
            ollama_port= $ (prompt_input "Ollama API port" "11434")
        done
        CONFIG_VALUES[OLLAMA_PORT]=" $ ollama_port"
    fi
    
    # WebUI port
    if [[ " $ {CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]]; then
        local webui_port= $ (prompt_input "WebUI port" "8080")
        while ! validate_port " $ webui_port" || ! check_port_available "$webui_port"; do
            log_error "Port  $ webui_port is invalid or already in use"
            webui_port= $ (prompt_input "WebUI port" "8080")
        done
        CONFIG_VALUES[WEBUI_PORT]=" $ webui_port"
    fi
    
    # n8n port
    if [[ " $ {CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        local n8n_port= $ (prompt_input "n8n port" "5678")
        while ! validate_port " $ n8n_port" || ! check_port_available "$n8n_port"; then
            log_error "Port  $ n8n_port is invalid or already in use"
            n8n_port= $ (prompt_input "n8n port" "5678")
        done
        CONFIG_VALUES[N8N_PORT]=" $ n8n_port"
    fi
    
    # PostgreSQL port
    if [[ " $ {CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
        local postgres_port= $ (prompt_input "PostgreSQL port" "5432")
        while ! validate_port " $ postgres_port" || ! check_port_available "$postgres_port"; do
            log_error "Port  $ postgres_port is invalid or already in use"
            postgres_port= $ (prompt_input "PostgreSQL port" "5432")
        done
        CONFIG_VALUES[POSTGRES_PORT]=" $ postgres_port"
    fi
    
    # Redis port
    if [[ " $ {CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
        local redis_port= $ (prompt_input "Redis port" "6379")
        while ! validate_port " $ redis_port" || ! check_port_available "$redis_port"; then
            log_error "Port  $ redis_port is invalid or already in use"
            redis_port= $ (prompt_input "Redis port" "6379")
        done
        CONFIG_VALUES[REDIS_PORT]=" $ redis_port"
    fi
    
    # Nginx ports
    if [[ " $ {CONFIG_VALUES[INSTALL_NGINX]}" == "true" ]]; then
        local http_port= $ (prompt_input "Nginx HTTP port" "80")
        while ! validate_port " $ http_port" || ! check_port_available "$http_port"; then
            log_error "Port  $ http_port is invalid or already in use"
            http_port= $ (prompt_input "Nginx HTTP port" "80")
        done
        CONFIG_VALUES[NGINX_HTTP_PORT]=" $ http_port"
        
        local https_port= $ (prompt_input "Nginx HTTPS port" "443")
        while ! validate_port " $ https_port" || ! check_port_available " $ https_port"; then
            log_error "Port  $ https_port is invalid or already in use"
            https_port= $ (prompt_input "Nginx HTTPS port" "443")
        done
        CONFIG_VALUES[NGINX_HTTPS_PORT]=" $ https_port"
    fi
    
    # Monitoring ports
    if [[ " $ {CONFIG_VALUES[INSTALL_MONITORING]}" == "true" ]]; then
        local prometheus_port= $ (prompt_input "Prometheus port" "9090")
        CONFIG_VALUES[PROMETHEUS_PORT]=" $ prometheus_port"
        
        local grafana_port= $ (prompt_input "Grafana port" "3000")
        CONFIG_VALUES[GRAFANA_PORT]=" $ grafana_port"
    fi
    
    log_success "Port configuration complete"
}

step_05_storage_config() {
    log_step "Step 5/27: Storage Configuration"
    
    echo "Select storage type for persistent data:"
    local storage_type= $ (prompt_select "Storage type:" "docker-volumes" "bind-mounts")
    CONFIG_VALUES[STORAGE_TYPE]=" $ storage_type"
    
    if [[ " $ storage_type" == "bind-mounts" ]]; then
        local data_dir= $ (prompt_input "Data directory path" "${PROJECT_ROOT}/data")
        mkdir -p " $ data_dir"
        CONFIG_VALUES[DATA_DIR]=" $ data_dir"
        log_info "Data directory:  $ data_dir"
    else
        CONFIG_VALUES[DATA_DIR]=""
        log_info "Using Docker volumes for storage"
    fi
    
    # Ollama model storage
    if [[ " $ {CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        local ollama_models_dir= $ (prompt_input "Ollama models directory" " $ {PROJECT_ROOT}/models")
        mkdir -p " $ ollama_models_dir"
        CONFIG_VALUES[OLLAMA_MODELS_DIR]=" $ ollama_models_dir"
    fi
}

step_06_database_config() {
    log_step "Step 6/27: Database Configuration"
    
    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
        log_info "Configuring PostgreSQL..."
        
        local postgres_user= $ (prompt_input "PostgreSQL username" "aiplatform")
        CONFIG_VALUES[POSTGRES_USER]=" $ postgres_user"
        
        local postgres_password= $ (prompt_password "PostgreSQL password")
        if [[ -z " $ postgres_password" ]]; then
            postgres_password= $ (generate_random_string 32)
            log_info "Generated random PostgreSQL password"
        fi
        CONFIG_VALUES[POSTGRES_PASSWORD]=" $ postgres_password"
        
        local postgres_db= $ (prompt_input "PostgreSQL database name" "aiplatform")
        CONFIG_VALUES[POSTGRES_DB]=" $ postgres_db"
        
        # Connection pooling
        CONFIG_VALUES[POSTGRES_MAX_CONNECTIONS]= $ (prompt_input "Max connections" "100")
        CONFIG_VALUES[POSTGRES_SHARED_BUFFERS]= $ (prompt_input "Shared buffers (MB)" "256")
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
        log_info "Configuring Redis..."
        
        if prompt_yes_no "Enable Redis password protection?" "y"; then
            local redis_password= $ (prompt_password "Redis password")
            if [[ -z " $ redis_password" ]]; then
                redis_password= $ (generate_random_string 32)
                log_info "Generated random Redis password"
            fi
            CONFIG_VALUES[REDIS_PASSWORD]=" $ redis_password"
        else
            CONFIG_VALUES[REDIS_PASSWORD]=""
        fi
        
        CONFIG_VALUES[REDIS_MAXMEMORY]= $ (prompt_input "Redis max memory (MB)" "512")
        CONFIG_VALUES[REDIS_MAXMEMORY_POLICY]= $ (prompt_select "Eviction policy:" "allkeys-lru" "volatile-lru" "allkeys-lfu" "volatile-lfu")
    fi
}

step_07_proxy_config() {
    log_step "Step 7/27: Reverse Proxy Configuration"
    
    if [[ "${CONFIG_VALUES[INSTALL_NGINX]}" == "true" ]]; then
        local use_domain=$(prompt_yes_no "Configure domain names?" "n")
        
        if  $ use_domain; then
            CONFIG_VALUES[USE_DOMAIN]="true"
            
            if [[ " $ {CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]]; then
                local webui_domain= $ (prompt_input "WebUI domain" "webui.example.com")
                while ! validate_domain " $ webui_domain"; do
                    log_error "Invalid domain format"
                    webui_domain= $ (prompt_input "WebUI domain" "webui.example.com")
                done
                CONFIG_VALUES[WEBUI_DOMAIN]=" $ webui_domain"
            fi
            
            if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
                local n8n_domain= $ (prompt_input "n8n domain" "n8n.example.com")
                while ! validate_domain " $ n8n_domain"; do
                    log_error "Invalid domain format"
                    n8n_domain= $ (prompt_input "n8n domain" "n8n.example.com")
                done
                CONFIG_VALUES[N8N_DOMAIN]=" $ n8n_domain"
            fi
            
            if [[ "${CONFIG_VALUES[INSTALL_MONITORING]}" == "true" ]]; then
                local grafana_domain= $ (prompt_input "Grafana domain" "grafana.example.com")
                CONFIG_VALUES[GRAFANA_DOMAIN]=" $ grafana_domain"
            fi
        else
            CONFIG_VALUES[USE_DOMAIN]="false"
        fi
        
        # SSL Configuration
        if  $ use_domain && prompt_yes_no "Enable SSL/TLS?" "y"; then
            CONFIG_VALUES[ENABLE_SSL]="true"
            
            local ssl_method= $ (prompt_select "SSL certificate method:" "letsencrypt" "self-signed" "existing")
            CONFIG_VALUES[SSL_METHOD]=" $ ssl_method"
            
            if [[ " $ ssl_method" == "letsencrypt" ]]; then
                CONFIG_VALUES[SSL_EMAIL]= $ (prompt_input "Email for Let's Encrypt")
                CONFIG_VALUES[SSL_STAGING]= $ (prompt_yes_no "Use Let's Encrypt staging (for testing)?" "n" && echo "true" || echo "false")
            elif [[ " $ ssl_method" == "existing" ]]; then
                CONFIG_VALUES[SSL_CERT_PATH]= $ (prompt_input "Path to SSL certificate")
                CONFIG_VALUES[SSL_KEY_PATH]= $ (prompt_input "Path to SSL private key")
            fi
        else
            CONFIG_VALUES[ENABLE_SSL]="false"
        fi
    fi
}

step_08_auth_config() {
    log_step "Step 8/27: Authentication Configuration"
    
    # WebUI authentication
    if [[ " $ {CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]]; then
        log_info "Configuring WebUI authentication..."
        
        CONFIG_VALUES[WEBUI_SECRET_KEY]= $ (generate_random_string 64)
        
        if prompt_yes_no "Enable WebUI user registration?" "y"; then
            CONFIG_VALUES[ENABLE_SIGNUP]="true"
        else
            CONFIG_VALUES[ENABLE_SIGNUP]="false"
        fi
        
        if prompt_yes_no "Enable OAuth authentication?" "n"; then
            CONFIG_VALUES[ENABLE_OAUTH]="true"
            
            # OAuth providers
            if prompt_yes_no "Configure Google OAuth?" "n"; then
                CONFIG_VALUES[OAUTH_GOOGLE_CLIENT_ID]= $ (prompt_input "Google Client ID")
                CONFIG_VALUES[OAUTH_GOOGLE_CLIENT_SECRET]= $ (prompt_password "Google Client Secret")
            fi
            
            if prompt_yes_no "Configure GitHub OAuth?" "n"; then
                CONFIG_VALUES[OAUTH_GITHUB_CLIENT_ID]= $ (prompt_input "GitHub Client ID")
                CONFIG_VALUES[OAUTH_GITHUB_CLIENT_SECRET]= $ (prompt_password "GitHub Client Secret")
            fi
        else
            CONFIG_VALUES[ENABLE_OAUTH]="false"
        fi
    fi
    
    # n8n authentication
    if [[ " $ {CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        log_info "Configuring n8n authentication..."
        
        CONFIG_VALUES[N8N_ENCRYPTION_KEY]= $ (generate_random_string 64)
        
        local n8n_user_email= $ (prompt_input "n8n admin email" "admin@example.com")
        CONFIG_VALUES[N8N_USER_EMAIL]=" $ n8n_user_email"
        
        local n8n_user_password= $ (prompt_password "n8n admin password")
        if [[ -z " $ n8n_user_password" ]]; then
            n8n_user_password= $ (generate_random_string 24)
            log_info "Generated random n8n password"
        fi
        CONFIG_VALUES[N8N_USER_PASSWORD]=" $ n8n_user_password"
    fi
    
    # Basic auth for monitoring
    if [[ " $ {CONFIG_VALUES[INSTALL_MONITORING]}" == "true" ]]; then
        log_info "Configuring monitoring authentication..."
        
        local grafana_admin_user= $ (prompt_input "Grafana admin username" "admin")
        CONFIG_VALUES[GRAFANA_ADMIN_USER]=" $ grafana_admin_user"
        
        local grafana_admin_password= $ (prompt_password "Grafana admin password")
        if [[ -z " $ grafana_admin_password" ]]; then
            grafana_admin_password= $ (generate_random_string 24)
            log_info "Generated random Grafana password"
        fi
        CONFIG_VALUES[GRAFANA_ADMIN_PASSWORD]=" $ grafana_admin_password"
    fi
}

step_09_monitoring_config() {
    log_step "Step 9/27: Monitoring & Logging Configuration"
    
    if [[ "${CONFIG_VALUES[INSTALL_MONITORING]}" == "true" ]]; then
        CONFIG_VALUES[PROMETHEUS_RETENTION]= $ (prompt_input "Prometheus data retention (days)" "15")
        CONFIG_VALUES[PROMETHEUS_SCRAPE_INTERVAL]= $ (prompt_input "Metrics scrape interval (seconds)" "15")
        
        if prompt_yes_no "Enable alerting?" "y"; then
            CONFIG_VALUES[ENABLE_ALERTING]="true"
            CONFIG_VALUES[ALERT_EMAIL]= $ (prompt_input "Alert notification email")
        else
            CONFIG_VALUES[ENABLE_ALERTING]="false"
        fi
    fi
    
    # Log configuration
    local log_level= $ (prompt_select "Application log level:" "info" "debug" "warn" "error")
    CONFIG_VALUES[LOG_LEVEL]=" $ log_level"
    
    CONFIG_VALUES[LOG_RETENTION_DAYS]= $ (prompt_input "Log retention (days)" "30")
    
    if prompt_yes_no "Enable structured JSON logging?" "y"; then
        CONFIG_VALUES[LOG_FORMAT]="json"
    else
        CONFIG_VALUES[LOG_FORMAT]="text"
    fi
}

step_10_network_config() {
    log_step "Step 10/27: Network Configuration"
    
    local network_mode= $ (prompt_select "Docker network mode:" "bridge" "host")
    CONFIG_VALUES[NETWORK_MODE]=" $ network_mode"
    
    if [[ " $ network_mode" == "bridge" ]]; then
        CONFIG_VALUES[NETWORK_SUBNET]= $ (prompt_input "Network subnet" "172.28.0.0/16")
        CONFIG_VALUES[NETWORK_GATEWAY]= $ (prompt_input "Network gateway" "172.28.0.1")
    fi
    
    # IP whitelisting
    if prompt_yes_no "Enable IP whitelisting?" "n"; then
        CONFIG_VALUES[ENABLE_IP_WHITELIST]="true"
        CONFIG_VALUES[ALLOWED_IPS]= $ (prompt_input "Allowed IP addresses (comma-separated)" "127.0.0.1,::1")
    else
        CONFIG_VALUES[ENABLE_IP_WHITELIST]="false"
    fi
    
    # Rate limiting
    if [[ "${CONFIG_VALUES[INSTALL_NGINX]}" == "true" ]]; then
        if prompt_yes_no "Enable rate limiting?" "y"; then
            CONFIG_VALUES[ENABLE_RATE_LIMIT]="true"
            CONFIG_VALUES[RATE_LIMIT_REQUESTS]= $ (prompt_input "Max requests per minute" "60")
        else
            CONFIG_VALUES[ENABLE_RATE_LIMIT]="false"
        fi
    fi
}

step_11_resource_limits() {
    log_step "Step 11/27: Resource Limits"
    
    if prompt_yes_no "Configure container resource limits?" "y"; then
        CONFIG_VALUES[ENABLE_RESOURCE_LIMITS]="true"
        
        if [[ " $ {CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
            CONFIG_VALUES[OLLAMA_MEM_LIMIT]= $ (prompt_input "Ollama memory limit (e.g., 4g)" "4g")
            CONFIG_VALUES[OLLAMA_CPU_LIMIT]= $ (prompt_input "Ollama CPU limit (cores)" "2")
        fi
        
        if [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]]; then
            CONFIG_VALUES[WEBUI_MEM_LIMIT]= $ (prompt_input "WebUI memory limit" "1g")
            CONFIG_VALUES[WEBUI_CPU_LIMIT]= $ (prompt_input "WebUI CPU limit" "1")
        fi
        
        if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
            CONFIG_VALUES[N8N_MEM_LIMIT]= $ (prompt_input "n8n memory limit" "2g")
            CONFIG_VALUES[N8N_CPU_LIMIT]= $ (prompt_input "n8n CPU limit" "1")
        fi
        
        if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
            CONFIG_VALUES[POSTGRES_MEM_LIMIT]= $ (prompt_input "PostgreSQL memory limit" "2g")
            CONFIG_VALUES[POSTGRES_CPU_LIMIT]= $ (prompt_input "PostgreSQL CPU limit" "2")
        fi
    else
        CONFIG_VALUES[ENABLE_RESOURCE_LIMITS]="false"
    fi
}

step_12_backup_config() {
    log_step "Step 12/27: Backup Configuration"
    
    if prompt_yes_no "Configure automated backups?" "y"; then
        CONFIG_VALUES[ENABLE_BACKUPS]="true"
        
        CONFIG_VALUES[BACKUP_PATH]= $ (prompt_input "Backup directory" " $ {PROJECT_ROOT}/backups")
        mkdir -p "${CONFIG_VALUES[BACKUP_PATH]}"
        
        echo "Backup schedule options:"
        echo "  1. Daily at 2 AM"
        echo "  2. Every 6 hours"
        echo "  3. Weekly (Sunday 2 AM)"
        echo "  4. Custom cron expression"
        
        local schedule_choice= $ (prompt_select "Select backup schedule:" "daily" "every-6-hours" "weekly" "custom")
        
        case " $ schedule_choice" in
            daily)
                CONFIG_VALUES[BACKUP_SCHEDULE]="0 2 * * *"
                ;;
            every-6-hours)
                CONFIG_VALUES[BACKUP_SCHEDULE]="0 */6 * * *"
                ;;
            weekly)
                CONFIG_VALUES[BACKUP_SCHEDULE]="0 2 * * 0"
                ;;
            custom)
                CONFIG_VALUES[BACKUP_SCHEDULE]= $ (prompt_input "Enter cron expression")
                ;;
        esac
        
        CONFIG_VALUES[BACKUP_RETENTION_DAYS]= $ (prompt_input "Backup retention (days)" "7")
        
        if prompt_yes_no "Enable backup encryption?" "y"; then
            CONFIG_VALUES[BACKUP_ENCRYPTION]="true"
            local backup_password= $ (prompt_password "Backup encryption password")
            CONFIG_VALUES[BACKUP_PASSWORD]=" $ backup_password"
        else
            CONFIG_VALUES[BACKUP_ENCRYPTION]="false"
        fi
        
        if prompt_yes_no "Enable remote backup?" "n"; then
            CONFIG_VALUES[ENABLE_REMOTE_BACKUP]="true"
            
            local backup_method= $ (prompt_select "Remote backup method:" "s3" "rsync" "scp")
            CONFIG_VALUES[REMOTE_BACKUP_METHOD]=" $ backup_method"
            
            case " $ backup_method" in
                s3)
                    CONFIG_VALUES[S3_BUCKET]= $ (prompt_input "S3 bucket name")
                    CONFIG_VALUES[S3_REGION]= $ (prompt_input "S3 region" "us-east-1")
                    CONFIG_VALUES[AWS_ACCESS_KEY_ID]= $ (prompt_input "AWS Access Key ID")
                    CONFIG_VALUES[AWS_SECRET_ACCESS_KEY]= $ (prompt_password "AWS Secret Access Key")
                    ;;
                rsync|scp)
                    CONFIG_VALUES[REMOTE_HOST]= $ (prompt_input "Remote host")
                    CONFIG_VALUES[REMOTE_USER]= $ (prompt_input "Remote user")
                    CONFIG_VALUES[REMOTE_PATH]= $ (prompt_input "Remote path")
                    ;;
            esac
        else
            CONFIG_VALUES[ENABLE_REMOTE_BACKUP]="false"
        fi
    else
        CONFIG_VALUES[ENABLE_BACKUPS]="false"
    fi
}

step_13_advanced_options() {
    log_step "Step 13/27: Advanced Options"
    
    # Timezone
    CONFIG_VALUES[TZ]= $ (prompt_input "Timezone" "UTC")
    
    # Update policy
    echo "Container update policy:"
    local update_policy= $ (prompt_select "Update policy:" "no" "on-failure" "always" "unless-stopped")
    CONFIG_VALUES[RESTART_POLICY]=" $ update_policy"
    
    # Environment-specific settings
    if [[ " $ {CONFIG_VALUES[ENVIRONMENT]}" == "production" ]]; then
        CONFIG_VALUES[ENABLE_DEBUG]="false"
        CONFIG_VALUES[ENABLE_AUTO_UPDATES]= $ (prompt_yes_no "Enable automatic security updates?" "y" && echo "true" || echo "false")
    else
        CONFIG_VALUES[ENABLE_DEBUG]="true"
        CONFIG_VALUES[ENABLE_AUTO_UPDATES]="false"
    fi
    
    # Custom environment variables
    if prompt_yes_no "Add custom environment variables?" "n"; then
        CONFIG_VALUES[ENABLE_CUSTOM_ENV]="true"
        echo "Enter custom environment variables (format: KEY=VALUE, one per line, empty line to finish):"
        
        local custom_env=""
        while true; do
            read -r line
            [[ -z " $ line" ]] && break
            custom_env="${custom_env}${line}\n"
        done
        CONFIG_VALUES[CUSTOM_ENV]=" $ custom_env"
    else
        CONFIG_VALUES[ENABLE_CUSTOM_ENV]="false"
    fi
}

# Continue with remaining steps...
step_14_ollama_models() {
    log_step "Step 14/27: Ollama Model Configuration"
    
    if [[ " $ {CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        echo "Configure Ollama models to pre-download:"
        
        if prompt_yes_no "Pre-download models during installation?" "y"; then
            CONFIG_VALUES[PREDOWNLOAD_MODELS]="true"
            
            echo "Available models:"
            echo "  1. llama2 (7B)"
            echo "  2. llama2:13b"
            echo "  3. mistral"
            echo "  4. codellama"
            echo "  5. Custom model"
            
            local models=""
            while true; do
                local model= $ (prompt_select "Select model (or 'done' to finish):" "llama2" "llama2:13b" "mistral" "codellama" "custom" "done")
                
                [[ " $ model" == "done" ]] && break
                
                if [[ " $ model" == "custom" ]]; then
                    model= $ (prompt_input "Enter custom model name")
                fi
                
                models="${models}${model},"
                log_info "Added model:  $ model"
            done
            
            CONFIG_VALUES[OLLAMA_MODELS]=" $ {models%,}"
        else
            CONFIG_VALUES[PREDOWNLOAD_MODELS]="false"
        fi
        
        # GPU configuration
        if prompt_yes_no "Enable GPU support for Ollama?" "n"; then
            CONFIG_VALUES[OLLAMA_GPU_ENABLED]="true"
            
            local gpu_type= $ (prompt_select "GPU type:" "nvidia" "amd" "intel")
            CONFIG_VALUES[OLLAMA_GPU_TYPE]=" $ gpu_type"
            
            if [[ " $ gpu_type" == "nvidia" ]]; then
                CONFIG_VALUES[OLLAMA_GPU_LAYERS]= $ (prompt_input "GPU layers" "35")
            fi
        else
            CONFIG_VALUES[OLLAMA_GPU_ENABLED]="false"
        fi
    fi
}

step_15_model_settings() {
    log_step "Step 15/27: Model Runtime Settings"
    
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        CONFIG_VALUES[OLLAMA_NUM_PARALLEL]= $ (prompt_input "Parallel request handling" "4")
        CONFIG_VALUES[OLLAMA_MAX_LOADED_MODELS]= $ (prompt_input "Max loaded models" "3")
        CONFIG_VALUES[OLLAMA_CONTEXT_LENGTH]= $ (prompt_input "Context window size" "4096")
        
        if prompt_yes_no "Enable model preloading?" "y"; then
            CONFIG_VALUES[OLLAMA_KEEP_ALIVE]="24h"
        else
            CONFIG_VALUES[OLLAMA_KEEP_ALIVE]="5m"
        fi
    fi
}

step_16_webui_features() {
    log_step "Step 16/27: WebUI Features"
    
    if [[ " $ {CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]]; then
        CONFIG_VALUES[WEBUI_NAME]= $ (prompt_input "WebUI application name" "AI Platform")
        
        if prompt_yes_no "Enable image generation?" "y"; then
            CONFIG_VALUES[ENABLE_IMAGE_GENERATION]="true"
            CONFIG_VALUES[IMAGE_GENERATION_ENGINE]= $ (prompt_select "Image generation engine:" "automatic1111" "comfyui" "disabled")
            
            if [[ "${CONFIG_VALUES[IMAGE_GENERATION_ENGINE]}" != "disabled" ]]; then
                CONFIG_VALUES[IMAGE_GENERATION_API]= $ (prompt_input "Image generation API URL")
            fi
        else
            CONFIG_VALUES[ENABLE_IMAGE_GENERATION]="false"
        fi
        
        if prompt_yes_no "Enable document RAG (Retrieval Augmented Generation)?" "y"; then
            CONFIG_VALUES[ENABLE_RAG]="true"
            CONFIG_VALUES[RAG_EMBEDDING_MODEL]= $ (prompt_input "Embedding model" "sentence-transformers/all-MiniLM-L6-v2")
            CONFIG_VALUES[CHUNK_SIZE]= $ (prompt_input "Document chunk size" "1500")
            CONFIG_VALUES[CHUNK_OVERLAP]= $ (prompt_input "Chunk overlap" "100")
        else
            CONFIG_VALUES[ENABLE_RAG]="false"
        fi
        
        if prompt_yes_no "Enable web search?" "n"; then
            CONFIG_VALUES[ENABLE_WEB_SEARCH]="true"
            
            local search_engine= $ (prompt_select "Search engine:" "searxng" "google" "duckduckgo")
            CONFIG_VALUES[SEARCH_ENGINE]=" $ search_engine"
            
            if [[ " $ search_engine" == "google" ]]; then
                CONFIG_VALUES[GOOGLE_API_KEY]= $ (prompt_input "Google API Key")
                CONFIG_VALUES[GOOGLE_CSE_ID]= $ (prompt_input "Google Custom Search Engine ID")
            elif [[ " $ search_engine" == "searxng" ]]; then
                CONFIG_VALUES[SEARXNG_URL]= $ (prompt_input "SearXNG instance URL" "https://searx.be")
            fi
        else
            CONFIG_VALUES[ENABLE_WEB_SEARCH]="false"
        fi
    fi
}

step_17_n8n_config() {
    log_step "Step 17/27: n8n Workflow Configuration"
    
    if [[ " $ {CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        CONFIG_VALUES[N8N_EDITOR_BASE_URL]= $ (prompt_input "n8n editor base URL" "http://localhost: $ {CONFIG_VALUES[N8N_PORT]}")
        CONFIG_VALUES[N8N_WEBHOOK_URL]= $ (prompt_input "n8n webhook URL" "http://localhost: $ {CONFIG_VALUES[N8N_PORT]}")
        
        CONFIG_VALUES[N8N_EXECUTIONS_PROCESS]= $ (prompt_select "Execution mode:" "main" "own")
        
        CONFIG_VALUES[N8N_EXECUTIONS_DATA_SAVE_ON_ERROR]= $ (prompt_yes_no "Save execution data on error?" "y" && echo "all" || echo "none")
        CONFIG_VALUES[N8N_EXECUTIONS_DATA_SAVE_ON_SUCCESS]= $ (prompt_yes_no "Save execution data on success?" "n" && echo "all" || echo "none")
        
        CONFIG_VALUES[N8N_EXECUTIONS_DATA_PRUNE]= $ (prompt_yes_no "Enable execution data pruning?" "y" && echo "true" || echo "false")
        
        if [[ "${CONFIG_VALUES[N8N_EXECUTIONS_DATA_PRUNE]}" == "true" ]]; then
            CONFIG_VALUES[N8N_EXECUTIONS_DATA_MAX_AGE]= $ (prompt_input "Max execution age (hours)" "336")
        fi
        
        if prompt_yes_no "Enable community nodes?" "y"; then
            CONFIG_VALUES[N8N_COMMUNITY_NODES_ENABLED]="true"
        else
            CONFIG_VALUES[N8N_COMMUNITY_NODES_ENABLED]="false"
        fi
    fi
}

step_18_integration_apis() {
    log_step "Step 18/27: External API Integration"
    
    if prompt_yes_no "Configure external API integrations?" "n"; then
        CONFIG_VALUES[ENABLE_EXTERNAL_APIS]="true"
        
        # OpenAI API
        if prompt_yes_no "Add OpenAI API?" "n"; then
            CONFIG_VALUES[OPENAI_API_KEY]= $ (prompt_password "OpenAI API Key")
        fi
        
        # Anthropic API
        if prompt_yes_no "Add Anthropic (Claude) API?" "n"; then
            CONFIG_VALUES[ANTHROPIC_API_KEY]= $ (prompt_password "Anthropic API Key")
        fi
        
        # Hugging Face
        if prompt_yes_no "Add Hugging Face API?" "n"; then
            CONFIG_VALUES[HUGGINGFACE_API_KEY]= $ (prompt_password "Hugging Face API Token")
        fi
        
        # Custom APIs
        if prompt_yes_no "Add custom API endpoints?" "n"; then
            echo "Enter custom API configurations (format: NAME=URL, one per line, empty to finish):"
            local custom_apis=""
            while true; do
                read -r line
                [[ -z " $ line" ]] && break
                custom_apis=" $ {custom_apis}${line}\n"
            done
            CONFIG_VALUES[CUSTOM_APIS]=" $ custom_apis"
        fi
    else
        CONFIG_VALUES[ENABLE_EXTERNAL_APIS]="false"
    fi
}

step_19_email_config() {
    log_step "Step 19/27: Email Configuration"
    
    if prompt_yes_no "Configure email notifications?" "n"; then
        CONFIG_VALUES[ENABLE_EMAIL]="true"
        
        CONFIG_VALUES[SMTP_HOST]= $ (prompt_input "SMTP host")
        CONFIG_VALUES[SMTP_PORT]= $ (prompt_input "SMTP port" "587")
        CONFIG_VALUES[SMTP_USER]= $ (prompt_input "SMTP username")
        CONFIG_VALUES[SMTP_PASSWORD]= $ (prompt_password "SMTP password")
        CONFIG_VALUES[SMTP_FROM]= $ (prompt_input "From email address")
        
        CONFIG_VALUES[SMTP_SECURE]= $ (prompt_yes_no "Use TLS?" "y" && echo "true" || echo "false")
    else
        CONFIG_VALUES[ENABLE_EMAIL]="false"
    fi
}

step_20_webhook_config() {
    log_step "Step 20/27: Webhook Configuration"
    
    if prompt_yes_no "Configure webhooks?" "n"; then
        CONFIG_VALUES[ENABLE_WEBHOOKS]="true"
        
        echo "Enter webhook URLs (one per line, empty to finish):"
        local webhooks=""
        while true; do
            read -r line
            [[ -z " $ line" ]] && break
            webhooks="${webhooks}${line},"
        done
        CONFIG_VALUES[WEBHOOK_URLS]="${webhooks%,}"
        
        CONFIG_VALUES[WEBHOOK_SECRET]= $ (generate_random_string 32)
    else
        CONFIG_VALUES[ENABLE_WEBHOOKS]="false"
    fi
}

step_21_cors_config() {
    log_step "Step 21/27: CORS Configuration"
    
    if [[ " $ {CONFIG_VALUES[ENVIRONMENT]}" == "development" ]]; then
        CONFIG_VALUES[CORS_ORIGINS]="*"
    else
        if prompt_yes_no "Configure CORS allowed origins?" "y"; then
            CONFIG_VALUES[CORS_ORIGINS]= $ (prompt_input "Allowed origins (comma-separated)" "https://*.example.com")
        else
            CONFIG_VALUES[CORS_ORIGINS]="*"
        fi
    fi
    
    CONFIG_VALUES[CORS_METHODS]= $ (prompt_input "Allowed methods" "GET,POST,PUT,DELETE,OPTIONS")
    CONFIG_VALUES[CORS_CREDENTIALS]= $ (prompt_yes_no "Allow credentials?" "y" && echo "true" || echo "false")
}

step_22_cache_config() {
    log_step "Step 22/27: Caching Strategy"
    
    if [[ " $ {CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
        CONFIG_VALUES[ENABLE_CACHE]="true"
        CONFIG_VALUES[CACHE_TTL]= $ (prompt_input "Default cache TTL (seconds)" "3600")
        CONFIG_VALUES[CACHE_MAX_SIZE]= $ (prompt_input "Max cache size (MB)" "512")
    else
        CONFIG_VALUES[ENABLE_CACHE]="false"
    fi
}

step_23_session_config() {
    log_step "Step 23/27: Session Management"
    
    CONFIG_VALUES[SESSION_SECRET]= $ (generate_random_string 64)
    CONFIG_VALUES[SESSION_TIMEOUT]= $ (prompt_input "Session timeout (minutes)" "60")
    
    if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
        CONFIG_VALUES[SESSION_STORE]="redis"
    else
        CONFIG_VALUES[SESSION_STORE]="memory"
    fi
}

step_24_security_hardening() {
    log_step "Step 24/27: Security Hardening"
    
    if [[ "${CONFIG_VALUES[ENVIRONMENT]}" == "production" ]]; then
        CONFIG_VALUES[ENABLE_SECURITY_HEADERS]="true"
        CONFIG_VALUES[ENABLE_CSRF_PROTECTION]="true"
        CONFIG_VALUES[ENABLE_XSS_PROTECTION]="true"
        CONFIG_VALUES[ENABLE_CLICKJACKING_PROTECTION]="true"
        
        CONFIG_VALUES[PASSWORD_MIN_LENGTH]= $ (prompt_input "Minimum password length" "12")
        CONFIG_VALUES[PASSWORD_REQUIRE_SPECIAL]= $ (prompt_yes_no "Require special characters in passwords?" "y" && echo "true" || echo "false")
        
        CONFIG_VALUES[MAX_LOGIN_ATTEMPTS]= $ (prompt_input "Max login attempts" "5")
        CONFIG_VALUES[LOCKOUT_DURATION]= $ (prompt_input "Account lockout duration (minutes)" "15")
        
        if prompt_yes_no "Enable two-factor authentication (2FA)?" "n"; then
            CONFIG_VALUES[ENABLE_2FA]="true"
        else
            CONFIG_VALUES[ENABLE_2FA]="false"
        fi
    else
        CONFIG_VALUES[ENABLE_SECURITY_HEADERS]="false"
        CONFIG_VALUES[ENABLE_CSRF_PROTECTION]="false"
        CONFIG_VALUES[ENABLE_2FA]="false"
    fi
    
    # Firewall rules
    if prompt_yes_no "Configure UFW firewall rules?" "n"; then
        CONFIG_VALUES[ENABLE_UFW]="true"
    else
        CONFIG_VALUES[ENABLE_UFW]="false"
    fi
}

step_25_health_checks() {
    log_step "Step 25/27: Health Check Configuration"
    
    CONFIG_VALUES[HEALTH_CHECK_INTERVAL]= $ (prompt_input "Health check interval (seconds)" "30")
    CONFIG_VALUES[HEALTH_CHECK_TIMEOUT]= $ (prompt_input "Health check timeout (seconds)" "5")
    CONFIG_VALUES[HEALTH_CHECK_RETRIES]= $ (prompt_input "Health check retries" "3")
    
    if prompt_yes_no "Enable startup health delay?" "y"; then
        CONFIG_VALUES[HEALTH_CHECK_START_PERIOD]= $ (prompt_input "Startup grace period (seconds)" "60")
    else
        CONFIG_VALUES[HEALTH_CHECK_START_PERIOD]="0"
    fi
}

step_26_performance_tuning() {
    log_step "Step 26/27: Performance Tuning"
    
    # Worker configuration
    if [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]] || [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        CONFIG_VALUES[WORKER_PROCESSES]= $ (prompt_input "Worker processes" "auto")
        CONFIG_VALUES[WORKER_CONNECTIONS]= $ (prompt_input "Worker connections" "1024")
    fi
    
    # Buffer sizes
    CONFIG_VALUES[CLIENT_MAX_BODY_SIZE]= $ (prompt_input "Max upload size (MB)" "100")
    
    # Timeouts
    CONFIG_VALUES[REQUEST_TIMEOUT]= $ (prompt_input "Request timeout (seconds)" "300")
    CONFIG_VALUES[KEEPALIVE_TIMEOUT]= $ (prompt_input "Keepalive timeout (seconds)" "65")
    
    # Connection pooling
    if [[ " $ {CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
        CONFIG_VALUES[DB_POOL_MIN]= $ (prompt_input "Database pool min connections" "2")
        CONFIG_VALUES[DB_POOL_MAX]= $ (prompt_input "Database pool max connections" "10")
    fi
}

step_27_final_review() {
    log_step "Step 27/27: Final Review"
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "                  CONFIGURATION SUMMARY"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    echo "${BOLD}Project Information:${NC}"
    echo "  Project Name: ${CONFIG_VALUES[PROJECT_NAME]}"
    echo "  Environment: ${CONFIG_VALUES[ENVIRONMENT]}"
    echo "  Installation Type: ${CONFIG_VALUES[INSTALL_TYPE]}"
    echo ""
    
    echo "${BOLD}Components:${NC}"
    [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]] && echo "  ✓ Ollama (Port: ${CONFIG_VALUES[OLLAMA_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]] && echo "  ✓ Open WebUI (Port: ${CONFIG_VALUES[WEBUI_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]] && echo "  ✓ n8n (Port: ${CONFIG_VALUES[N8N_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]] && echo "  ✓ PostgreSQL (Port: ${CONFIG_VALUES[POSTGRES_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]] && echo "  ✓ Redis (Port: ${CONFIG_VALUES[REDIS_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_NGINX]}" == "true" ]] && echo "  ✓ Nginx Reverse Proxy"
    [[ "${CONFIG_VALUES[INSTALL_MONITORING]}" == "true" ]] && echo "  ✓ Monitoring Stack"
    echo ""
    
    if [[ "${CONFIG_VALUES[USE_DOMAIN]}" == "true" ]]; then
        echo "${BOLD}Domains:${NC}"
        [[ -n "${CONFIG_VALUES[WEBUI_DOMAIN]:-}" ]] && echo "  WebUI: ${CONFIG_VALUES[WEBUI_DOMAIN]}"
        [[ -n "${CONFIG_VALUES[N8N_DOMAIN]:-}" ]] && echo "  n8n: ${CONFIG_VALUES[N8N_DOMAIN]}"
        [[ -n "${CONFIG_VALUES[GRAFANA_DOMAIN]:-}" ]] && echo "  Grafana: ${CONFIG_VALUES[GRAFANA_DOMAIN]}"
        echo ""
    fi
    
    if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]]; then
        echo "${BOLD}SSL/TLS:${NC}"
        echo "  Method: ${CONFIG_VALUES[SSL_METHOD]}"
        [[ -n "${CONFIG_VALUES[SSL_EMAIL]:-}" ]] && echo "  Email: ${CONFIG_VALUES[SSL_EMAIL]}"
        echo ""
    fi
    
    echo "${BOLD}Storage:${NC}"
    echo "  Type: ${CONFIG_VALUES[STORAGE_TYPE]}"
    [[ -n "${CONFIG_VALUES[DATA_DIR]:-}" ]] && echo "  Data Directory: ${CONFIG_VALUES[DATA_DIR]}"
    echo ""
    
    if [[ "${CONFIG_VALUES[ENABLE_BACKUPS]}" == "true" ]]; then
        echo "${BOLD}Backups:${NC}"
        echo "  Path: ${CONFIG_VALUES[BACKUP_PATH]}"
        echo "  Schedule: ${CONFIG_VALUES[BACKUP_SCHEDULE]}"
        echo "  Retention: ${CONFIG_VALUES[BACKUP_RETENTION_DAYS]} days"
        [[ "${CONFIG_VALUES[BACKUP_ENCRYPTION]}" == "true" ]] && echo "  Encryption: Enabled"
        echo ""
    fi
    
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    if ! prompt_yes_no "Is this configuration correct?" "y"; then
        log_warn "Configuration rejected. Please run the script again."
        exit 0
    fi
}

################################################################################
# CONFIGURATION GENERATION
################################################################################

generate_env_file() {
    log_step "Generating Environment Configuration"
    
    local env_file="${PROJECT_ROOT}/.env"
    
    cat > "$env_file" << EOF
################################################################################
# AI Platform Environment Configuration
# Generated:  $ (date)
################################################################################

# Project Configuration
PROJECT_NAME= $ {CONFIG_VALUES[PROJECT_NAME]}
ENVIRONMENT=${CONFIG_VALUES[ENVIRONMENT]}
COMPOSE_PROJECT_NAME=${CONFIG_VALUES[COMPOSE_PROJECT_NAME]}
TZ=${CONFIG_VALUES[TZ]}

# Installation Components
INSTALL_OLLAMA=${CONFIG_VALUES[INSTALL_OLLAMA]}
INSTALL_WEBUI=${CONFIG_VALUES[INSTALL_WEBUI]}
INSTALL_N8N=${CONFIG_VALUES[INSTALL_N8N]}
INSTALL_POSTGRES=${CONFIG_VALUES[INSTALL_POSTGRES]}
INSTALL_REDIS=${CONFIG_VALUES[INSTALL_REDIS]}
INSTALL_NGINX=${CONFIG_VALUES[INSTALL_NGINX]}
INSTALL_MONITORING=${CONFIG_VALUES[INSTALL_MONITORING]}

# Service Ports
EOF

    [[ -n "${CONFIG_VALUES[OLLAMA_PORT]:-}" ]] && echo "OLLAMA_PORT=${CONFIG_VALUES[OLLAMA_PORT]}" >> " $ env_file"
    [[ -n " $ {CONFIG_VALUES[WEBUI_PORT]:-}" ]] && echo "WEBUI_PORT=${CONFIG_VALUES[WEBUI_PORT]}" >> " $ env_file"
    [[ -n " $ {CONFIG_VALUES[N8N_PORT]:-}" ]] && echo "N8N_PORT=${CONFIG_VALUES[N8N_PORT]}" >> " $ env_file"
    [[ -n " $ {CONFIG_VALUES[POSTGRES_PORT]:-}" ]] && echo "POSTGRES_PORT=${CONFIG_VALUES[POSTGRES_PORT]}" >> " $ env_file"
    [[ -n " $ {CONFIG_VALUES[REDIS_PORT]:-}" ]] && echo "REDIS_PORT=${CONFIG_VALUES[REDIS_PORT]}" >> " $ env_file"

    cat >> " $ env_file" << EOF

# Database Configuration
EOF

    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
        cat >> " $ env_file" << EOF
POSTGRES_USER= $ {CONFIG_VALUES[POSTGRES_USER]}
POSTGRES_PASSWORD=${CONFIG_VALUES[POSTGRES_PASSWORD]}
POSTGRES_DB=${CONFIG_VALUES[POSTGRES_DB]}
POSTGRES_MAX_CONNECTIONS=${CONFIG_VALUES[POSTGRES_MAX_CONNECTIONS]}
POSTGRES_SHARED_BUFFERS=${CONFIG_VALUES[POSTGRES_SHARED_BUFFERS]}
DATABASE_URL=postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@postgres:\${POSTGRES_PORT}/\${POSTGRES_DB}
EOF
    fi

    if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
        cat >> " $ env_file" << EOF
REDIS_PASSWORD= $ {CONFIG_VALUES[REDIS_PASSWORD]:-}
REDIS_MAXMEMORY=${CONFIG_VALUES[REDIS_MAXMEMORY]}mb
REDIS_MAXMEMORY_POLICY=${CONFIG_VALUES[REDIS_MAXMEMORY_POLICY]}
EOF
        if [[ -n "${CONFIG_VALUES[REDIS_PASSWORD]:-}" ]]; then
            echo "REDIS_URL=redis://:\${REDIS_PASSWORD}@redis:\${REDIS_PORT}" >> " $ env_file"
        else
            echo "REDIS_URL=redis://redis:\ $ {REDIS_PORT}" >> " $ env_file"
        fi
    fi

    # WebUI Configuration
    if [[ " $ {CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]]; then
        cat >> " $ env_file" << EOF

# WebUI Configuration
WEBUI_SECRET_KEY= $ {CONFIG_VALUES[WEBUI_SECRET_KEY]}
WEBUI_NAME=${CONFIG_VALUES[WEBUI_NAME]}
ENABLE_SIGNUP=${CONFIG_VALUES[ENABLE_SIGNUP]}
OLLAMA_BASE_URL=http://ollama:11434
EOF

        [[ -n "${CONFIG_VALUES[WEBUI_DOMAIN]:-}" ]] && echo "WEBUI_DOMAIN=${CONFIG_VALUES[WEBUI_DOMAIN]}" >> " $ env_file"
        
        if [[ " $ {CONFIG_VALUES[ENABLE_RAG]}" == "true" ]]; then
            cat >> " $ env_file" << EOF
ENABLE_RAG=true
RAG_EMBEDDING_MODEL= $ {CONFIG_VALUES[RAG_EMBEDDING_MODEL]}
CHUNK_SIZE=${CONFIG_VALUES[CHUNK_SIZE]}
CHUNK_OVERLAP=${CONFIG_VALUES[CHUNK_OVERLAP]}
EOF
        fi
        
        if [[ "${CONFIG_VALUES[ENABLE_IMAGE_GENERATION]}" == "true" ]]; then
            cat >> " $ env_file" << EOF
ENABLE_IMAGE_GENERATION=true
IMAGE_GENERATION_ENGINE= $ {CONFIG_VALUES[IMAGE_GENERATION_ENGINE]}
IMAGE_GENERATION_API=${CONFIG_VALUES[IMAGE_GENERATION_API]:-}
EOF
        fi
    fi

    # n8n Configuration
    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        cat >> " $ env_file" << EOF

# n8n Configuration
N8N_ENCRYPTION_KEY= $ {CONFIG_VALUES[N8N_ENCRYPTION_KEY]}
N8N_USER_EMAIL=${CONFIG_VALUES[N8N_USER_EMAIL]}
N8N_USER_PASSWORD=${CONFIG_VALUES[N8N_USER_PASSWORD]}
N8N_EDITOR_BASE_URL=${CONFIG_VALUES[N8N_EDITOR_BASE_URL]}
N8N_WEBHOOK_URL=${CONFIG_VALUES[N8N_WEBHOOK_URL]}
N8N_EXECUTIONS_PROCESS=${CONFIG_VALUES[N8N_EXECUTIONS_PROCESS]}
N8N_EXECUTIONS_DATA_SAVE_ON_ERROR=${CONFIG_VALUES[N8N_EXECUTIONS_DATA_SAVE_ON_ERROR]}
N8N_EXECUTIONS_DATA_SAVE_ON_SUCCESS=${CONFIG_VALUES[N8N_EXECUTIONS_DATA_SAVE_ON_SUCCESS]}
N8N_EXECUTIONS_DATA_PRUNE=${CONFIG_VALUES[N8N_EXECUTIONS_DATA_PRUNE]}
N8N_EXECUTIONS_DATA_MAX_AGE=${CONFIG_VALUES[N8N_EXECUTIONS_DATA_MAX_AGE]:-168}
N8N_COMMUNITY_NODES_ENABLED=${CONFIG_VALUES[N8N_COMMUNITY_NODES_ENABLED]}
EOF
        [[ -n "${CONFIG_VALUES[N8N_DOMAIN]:-}" ]] && echo "N8N_DOMAIN=${CONFIG_VALUES[N8N_DOMAIN]}" >> "$env_file"
    fi

    # Ollama Configuration
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        cat >> "$env_file" << EOF

# Ollama Configuration
OLLAMA_MODELS=${CONFIG_VALUES[OLLAMA_MODELS]:-}
OLLAMA_NUM_PARALLEL=${CONFIG_VALUES[OLLAMA_NUM_PARALLEL]}
OLLAMA_MAX_LOADED_MODELS=${CONFIG_VALUES[OLLAMA_MAX_LOADED_MODELS]}
OLLAMA_KEEP_ALIVE=${CONFIG_VALUES[OLLAMA_KEEP_ALIVE]}
EOF

        if [[ "${CONFIG_VALUES[OLLAMA_GPU_ENABLED]}" == "true" ]]; then
            cat >> "$env_file" << EOF
OLLAMA_GPU_ENABLED=true
OLLAMA_GPU_TYPE=${CONFIG_VALUES[OLLAMA_GPU_TYPE]}
EOF
            [[ -n "${CONFIG_VALUES[OLLAMA_GPU_LAYERS]:-}" ]] && echo "OLLAMA_GPU_LAYERS=${CONFIG_VALUES[OLLAMA_GPU_LAYERS]}" >> "$env_file"
        fi
    fi

    # Nginx Configuration
    if [[ "${CONFIG_VALUES[INSTALL_NGINX]}" == "true" ]]; then
        cat >> "$env_file" << EOF

# Nginx Configuration
NGINX_HTTP_PORT=${CONFIG_VALUES[NGINX_HTTP_PORT]}
NGINX_HTTPS_PORT=${CONFIG_VALUES[NGINX_HTTPS_PORT]}
CLIENT_MAX_BODY_SIZE=${CONFIG_VALUES[CLIENT_MAX_BODY_SIZE]}m
EOF

        if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]]; then
            cat >> "$env_file" << EOF
ENABLE_SSL=true
SSL_METHOD=${CONFIG_VALUES[SSL_METHOD]}
SSL_EMAIL=${CONFIG_VALUES[SSL_EMAIL]:-}
EOF
        fi
    fi

    # Monitoring Configuration
    if [[ "${CONFIG_VALUES[INSTALL_MONITORING]}" == "true" ]]; then
        cat >> "$env_file" << EOF

# Monitoring Configuration
PROMETHEUS_PORT=${CONFIG_VALUES[PROMETHEUS_PORT]}
GRAFANA_PORT=${CONFIG_VALUES[GRAFANA_PORT]}
GRAFANA_ADMIN_USER=${CONFIG_VALUES[GRAFANA_ADMIN_USER]}
GRAFANA_ADMIN_PASSWORD=${CONFIG_VALUES[GRAFANA_ADMIN_PASSWORD]}
EOF
    fi

    # Security Configuration
    cat >> "$env_file" << EOF

# Security Configuration
SESSION_SECRET=${CONFIG_VALUES[SESSION_SECRET]}
SESSION_TIMEOUT=${CONFIG_VALUES[SESSION_TIMEOUT]}
CORS_ORIGINS=${CONFIG_VALUES[CORS_ORIGINS]}
CORS_METHODS=${CONFIG_VALUES[CORS_METHODS]}
CORS_CREDENTIALS=${CONFIG_VALUES[CORS_CREDENTIALS]}
EOF

    # Email Configuration
    if [[ "${CONFIG_VALUES[ENABLE_EMAIL]}" == "true" ]]; then
        cat >> "$env_file" << EOF

# Email Configuration
SMTP_HOST=${CONFIG_VALUES[SMTP_HOST]}
SMTP_PORT=${CONFIG_VALUES[SMTP_PORT]}
SMTP_USER=${CONFIG_VALUES[SMTP_USER]}
SMTP_PASSWORD=${CONFIG_VALUES[SMTP_PASSWORD]}
SMTP_FROM=${CONFIG_VALUES[SMTP_FROM]}
SMTP_SECURE=${CONFIG_VALUES[SMTP_SECURE]}
EOF
    fi

    # External APIs
    if [[ "${CONFIG_VALUES[ENABLE_EXTERNAL_APIS]}" == "true" ]]; then
        cat >> "$env_file" << EOF

# External APIs
EOF
        [[ -n "${CONFIG_VALUES[OPENAI_API_KEY]:-}" ]] && echo "OPENAI_API_KEY=${CONFIG_VALUES[OPENAI_API_KEY]}" >> "$env_file"
        [[ -n "${CONFIG_VALUES[ANTHROPIC_API_KEY]:-}" ]] && echo "ANTHROPIC_API_KEY=${CONFIG_VALUES[ANTHROPIC_API_KEY]}" >> "$env_file"
        [[ -n "${CONFIG_VALUES[HUGGINGFACE_API_KEY]:-}" ]] && echo "HUGGINGFACE_API_KEY=${CONFIG_VALUES[HUGGINGFACE_API_KEY]}" >> "$env_file"
    fi

    # Backup Configuration
    if [[ "${CONFIG_VALUES[ENABLE_BACKUPS]}" == "true" ]]; then
        cat >> "$env_file" << EOF

# Backup Configuration
BACKUP_PATH=${CONFIG_VALUES[BACKUP_PATH]}
BACKUP_RETENTION_DAYS=${CONFIG_VALUES[BACKUP_RETENTION_DAYS]}
BACKUP_ENCRYPTION=${CONFIG_VALUES[BACKUP_ENCRYPTION]}
EOF
        [[ -n "${CONFIG_VALUES[BACKUP_ENCRYPTION_PASSWORD]:-}" ]] && echo "BACKUP_ENCRYPTION_PASSWORD=${CONFIG_VALUES[BACKUP_ENCRYPTION_PASSWORD]}" >> "$env_file"
    fi

    # Resource Limits
    cat >> "$env_file" << EOF

# Resource Limits
EOF
    [[ -n "${CONFIG_VALUES[OLLAMA_CPU_LIMIT]:-}" ]] && echo "OLLAMA_CPU_LIMIT=${CONFIG_VALUES[OLLAMA_CPU_LIMIT]}" >> "$env_file"
    [[ -n "${CONFIG_VALUES[OLLAMA_MEMORY_LIMIT]:-}" ]] && echo "OLLAMA_MEMORY_LIMIT=${CONFIG_VALUES[OLLAMA_MEMORY_LIMIT]}" >> "$env_file"
    [[ -n "${CONFIG_VALUES[WEBUI_CPU_LIMIT]:-}" ]] && echo "WEBUI_CPU_LIMIT=${CONFIG_VALUES[WEBUI_CPU_LIMIT]}" >> "$env_file"
    [[ -n "${CONFIG_VALUES[WEBUI_MEMORY_LIMIT]:-}" ]] && echo "WEBUI_MEMORY_LIMIT=${CONFIG_VALUES[WEBUI_MEMORY_LIMIT]}" >> "$env_file"

    chmod 600 "$env_file"
    log_success "Environment file generated: $env_file"
}

generate_docker_compose() {
    log_step "Generating Docker Compose Configuration"

    local compose_file="${PROJECT_ROOT}/docker-compose.yml"

    cat > "$compose_file" << 'EOF'
version: '3.8'

networks:
  aiplatform:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/16

volumes:
EOF

    # Define volumes based on storage type
    if [[ "${CONFIG_VALUES[STORAGE_TYPE]}" == "docker-volumes" ]]; then
        [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]] && echo "  ollama_data:" >> "$compose_file"
        [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]] && echo "  webui_data:" >> "$compose_file"
        [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]] && echo "  n8n_data:" >> "$compose_file"
        [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]] && echo "  postgres_data:" >> "$compose_file"
        [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]] && echo "  redis_data:" >> "$compose_file"
        [[ "${CONFIG_VALUES[INSTALL_MONITORING]}" == "true" ]] && echo "  prometheus_data:" >> "$compose_file"
        [[ "${CONFIG_VALUES[INSTALL_MONITORING]}" == "true" ]] && echo "  grafana_data:" >> "$compose_file"
    fi

    cat >> "$compose_file" << 'EOF'

services:
EOF

    # Ollama Service
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'
  ollama:
    image: ollama/ollama:latest
    container_name: ${COMPOSE_PROJECT_NAME}_ollama
    restart: unless-stopped
    networks:
      - aiplatform
    ports:
      - "${OLLAMA_PORT}:11434"
    volumes:
EOF
        if [[ "${CONFIG_VALUES[STORAGE_TYPE]}" == "docker-volumes" ]]; then
            echo "      - ollama_data:/root/.ollama" >> "$compose_file"
        else
            echo "      - ${DATA_DIR}/ollama:/root/.ollama" >> "$compose_file"
        fi

        cat >> "$compose_file" << 'EOF'
    environment:
      - OLLAMA_NUM_PARALLEL=${OLLAMA_NUM_PARALLEL}
      - OLLAMA_MAX_LOADED_MODELS=${OLLAMA_MAX_LOADED_MODELS}
      - OLLAMA_KEEP_ALIVE=${OLLAMA_KEEP_ALIVE}
EOF

        if [[ "${CONFIG_VALUES[OLLAMA_GPU_ENABLED]}" == "true" ]]; then
            if [[ "${CONFIG_VALUES[OLLAMA_GPU_TYPE]}" == "nvidia" ]]; then
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

        cat >> "$compose_file" << 'EOF'
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
        cat >> "$compose_file" << 'EOF'
  postgres:
    image: postgres:16-alpine
    container_name: ${COMPOSE_PROJECT_NAME}_postgres
    restart: unless-stopped
    networks:
      - aiplatform
    ports:
      - "${POSTGRES_PORT}:5432"
    volumes:
EOF
        if [[ "${CONFIG_VALUES[STORAGE_TYPE]}" == "docker-volumes" ]]; then
            echo "      - postgres_data:/var/lib/postgresql/data" >> "$compose_file"
        else
            echo "      - ${DATA_DIR}/postgres:/var/lib/postgresql/data" >> "$compose_file"
        fi

        cat >> "$compose_file" << 'EOF'
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_MAX_CONNECTIONS=${POSTGRES_MAX_CONNECTIONS}
      - POSTGRES_SHARED_BUFFERS=${POSTGRES_SHARED_BUFFERS}MB
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

EOF
    fi

    # Redis Service
    if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'
  redis:
    image: redis:7-alpine
    container_name: ${COMPOSE_PROJECT_NAME}_redis
    restart: unless-stopped
    networks:
      - aiplatform
    ports:
      - "${REDIS_PORT}:6379"
    volumes:
EOF
        if [[ "${CONFIG_VALUES[STORAGE_TYPE]}" == "docker-volumes" ]]; then
            echo "      - redis_data:/data" >> "$compose_file"
        else
            echo "      - ${DATA_DIR}/redis:/data" >> "$compose_file"
        fi

        cat >> "$compose_file" << 'EOF'
    command: >
      redis-server
      --maxmemory ${REDIS_MAXMEMORY}
      --maxmemory-policy ${REDIS_MAXMEMORY_POLICY}
EOF
        if [[ -n "${CONFIG_VALUES[REDIS_PASSWORD]:-}" ]]; then
            echo "      --requirepass \${REDIS_PASSWORD}" >> "$compose_file"
        fi

        cat >> "$compose_file" << 'EOF'
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5

EOF
    fi

    # WebUI Service
    if [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'
  webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: ${COMPOSE_PROJECT_NAME}_webui
    restart: unless-stopped
    networks:
      - aiplatform
    ports:
      - "${WEBUI_PORT}:8080"
    volumes:
EOF
        if [[ "${CONFIG_VALUES[STORAGE_TYPE]}" == "docker-volumes" ]]; then
            echo "      - webui_data:/app/backend/data" >> "$compose_file"
        else
            echo "      - ${DATA_DIR}/webui:/app/backend/data" >> "$compose_file"
        fi

        cat >> "$compose_file" << 'EOF'
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}
      - WEBUI_NAME=${WEBUI_NAME}
      - ENABLE_SIGNUP=${ENABLE_SIGNUP}
EOF

        if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
            echo "      - DATABASE_URL=\${DATABASE_URL}" >> "$compose_file"
        fi

        if [[ "${CONFIG_VALUES[ENABLE_RAG]}" == "true" ]]; then
            cat >> "$compose_file" << 'EOF'
      - ENABLE_RAG=true
      - RAG_EMBEDDING_MODEL=${RAG_EMBEDDING_MODEL}
      - CHUNK_SIZE=${CHUNK_SIZE}
      - CHUNK_OVERLAP=${CHUNK_OVERLAP}
EOF
        fi

        cat >> "$compose_file" << 'EOF'
    depends_on:
      - ollama
EOF
        [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]] && echo "      - postgres" >> "$compose_file"

        cat >> "$compose_file" << 'EOF'
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3

EOF
    fi

    # n8n Service
    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'
  n8n:
    image: n8nio/n8n:latest
    container_name: ${COMPOSE_PROJECT_NAME}_n8n
    restart: unless-stopped
    networks:
      - aiplatform
    ports:
      - "${N8N_PORT}:5678"
    volumes:
EOF
        if [[ "${CONFIG_VALUES[STORAGE_TYPE]}" == "docker-volumes" ]]; then
            echo "      - n8n_data:/home/node/.n8n" >> "$compose_file"
        else
            echo "      - ${DATA_DIR}/n8n:/home/node/.n8n" >> "$compose_file"
        fi

        cat >> "$compose_file" << 'EOF'
    environment:
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_USER_MANAGEMENT_DISABLED=false
      - N8N_EMAIL=${N8N_USER_EMAIL}
      - N8N_PASSWORD=${N8N_USER_PASSWORD}
      - N8N_EDITOR_BASE_URL=${N8N_EDITOR_BASE_URL}
      - WEBHOOK_URL=${N8N_WEBHOOK_URL}
      - N8N_EXECUTIONS_PROCESS=${N8N_EXECUTIONS_PROCESS}
      - EXECUTIONS_DATA_SAVE_ON_ERROR=${N8N_EXECUTIONS_DATA_SAVE_ON_ERROR}
      - EXECUTIONS_DATA_SAVE_ON_SUCCESS=${N8N_EXECUTIONS_DATA_SAVE_ON_SUCCESS}
      - EXECUTIONS_DATA_PRUNE=${N8N_EXECUTIONS_DATA_PRUNE}
      - EXECUTIONS_DATA_MAX_AGE=${N8N_EXECUTIONS_DATA_MAX_AGE}
      - N8N_COMMUNITY_PACKAGES_ENABLED=${N8N_COMMUNITY_NODES_ENABLED}
EOF

        if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
            cat >> "$compose_file" << 'EOF'
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
EOF
        fi

        cat >> "$compose_file" << 'EOF'
    depends_on:
EOF
        [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]] && echo "      - postgres" >> "$compose_file"
        [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]] && echo "      - ollama" >> "$compose_file"

        cat >> "$compose_file" << 'EOF'
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3

EOF
    fi

    # Nginx Service
    if [[ "${CONFIG_VALUES[INSTALL_NGINX]}" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'
  nginx:
    image: nginx:alpine
    container_name: ${COMPOSE_PROJECT_NAME}_nginx
    restart: unless-stopped
    networks:
      - aiplatform
    ports:
      - "${NGINX_HTTP_PORT}:80"
      - "${NGINX_HTTPS_PORT}:443"
    volumes:
      - ./config/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./config/nginx/conf.d:/etc/nginx/conf.d:ro
EOF
        if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]]; then
            echo "      - ./config/nginx/ssl:/etc/nginx/ssl:ro" >> "$compose_file"
        fi

        cat >> "$compose_file" << 'EOF'
    depends_on:
EOF
        [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]] && echo "      - webui" >> "$compose_file"
        [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]] && echo "      - n8n" >> "$compose_file"

        cat >> "$compose_file" << 'EOF'
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3

EOF
    fi

    # Monitoring Services
    if [[ "${CONFIG_VALUES[INSTALL_MONITORING]}" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'
  prometheus:
    image: prom/prometheus:latest
    container_name: ${COMPOSE_PROJECT_NAME}_prometheus
    restart: unless-stopped
    networks:
      - aiplatform
    ports:
      - "${PROMETHEUS_PORT}:9090"
    volumes:
EOF
        if [[ "${CONFIG_VALUES[STORAGE_TYPE]}" == "docker-volumes" ]]; then
            echo "      - prometheus_data:/prometheus" >> "$compose_file"
        else
            echo "      - ${DATA_DIR}/prometheus:/prometheus" >> "$compose_file"
        fi

        cat >> "$compose_file" << 'EOF'
      - ./config/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 10s
      retries: 3

  grafana:
    image: grafana/grafana:latest
    container_name: ${COMPOSE_PROJECT_NAME}_grafana
    restart: unless-stopped
    networks:
      - aiplatform
    ports:
      - "${GRAFANA_PORT}:3000"
    volumes:
EOF
        if [[ "${CONFIG_VALUES[STORAGE_TYPE]}" == "docker-volumes" ]]; then
            echo "      - grafana_data:/var/lib/grafana" >> "$compose_file"
        else
            echo "      - ${DATA_DIR}/grafana:/var/lib/grafana" >> "$compose_file"
        fi

        cat >> "$compose_file" << 'EOF'
      - ./config/grafana/provisioning:/etc/grafana/provisioning:ro
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_SERVER_ROOT_URL=http://localhost:${GRAFANA_PORT}
    depends_on:
      - prometheus
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF
    fi

    log_success "Docker Compose file generated: $compose_file"
}

generate_nginx_config() {
    if [[ "${CONFIG_VALUES[INSTALL_NGINX]}" != "true" ]]; then
        return 0
    fi

    log_step "Generating Nginx Configuration"

    local nginx_dir="${CONFIG_DIR}/nginx"
    local conf_dir="${nginx_dir}/conf.d"

    mkdir -p "$conf_dir"

    # Main nginx.conf
    cat > "${nginx_dir}/nginx.conf" << 'EOF'
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
    client_max_body_size ${CLIENT_MAX_BODY_SIZE}m;

    # Gzip Settings
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript
               application/json application/javascript application/xml+rss
               application/rss+xml font/truetype font/opentype
               application/vnd.ms-fontobject image/svg+xml;

    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    # Include site configurations
    include /etc/nginx/conf.d/*.conf;
}
EOF

    # Health check endpoint
    cat > "${conf_dir}/health.conf" << 'EOF'
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
        if [[ "${CONFIG_VALUES[USE_DOMAIN]}" == "true" ]] && [[ -n "${CONFIG_VALUES[WEBUI_DOMAIN]:-}" ]]; then
            cat > "${conf_dir}/webui.conf" << EOF
server {
    listen 80;
    server_name ${CONFIG_VALUES[WEBUI_DOMAIN]};

EOF
            if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]]; then
                cat >> "${conf_d}/webui.conf" << EOF
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${CONFIG_VALUES[WEBUI_DOMAIN]};

    ssl_certificate /etc/nginx/ssl/${CONFIG_VALUES[WEBUI_DOMAIN]}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/${CONFIG_VALUES[WEBUI_DOMAIN]}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

EOF
            fi

            cat >> "${conf_d}/webui.conf" << 'EOF'
    location / {
        proxy_pass http://webui:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }
}
EOF
        fi
    fi

    # n8n configuration
    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        if [[ "${CONFIG_VALUES[USE_DOMAIN]}" == "true" ]] && [[ -n "${CONFIG_VALUES[N8N_DOMAIN]:-}" ]]; then
            cat > "${conf_d}/n8n.conf" << EOF
server {
    listen 80;
    server_name ${CONFIG_VALUES[N8N_DOMAIN]};

EOF
            if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]]; then
                cat >> "${conf_d}/n8n.conf" << EOF
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${CONFIG_VALUES[N8N_DOMAIN]};

    ssl_certificate /etc/nginx/ssl/${CONFIG_VALUES[N8N_DOMAIN]}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/${CONFIG_VALUES[N8N_DOMAIN]}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

EOF
            fi

            cat >> "${conf_d}/n8n.conf" << 'EOF'
    location / {
        proxy_pass http://n8n:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF
        fi
    fi

    log_success "Nginx configuration generated"
}

generate_monitoring_configs() {
    if [[ "${CONFIG_VALUES[INSTALL_MONITORING]}" != "true" ]]; then
        return 0
    fi

    log_step "Generating Monitoring Configurations"

    # Prometheus configuration
    local prom_dir="${CONFIG_DIR}/prometheus"
    mkdir -p "$prom_dir"

    cat > "${prom_dir}/prometheus.yml" << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'aiplatform'
    environment: '${ENVIRONMENT}'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

EOF

    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        cat >> "${prom_dir}/prometheus.yml" << 'EOF'
  - job_name: 'ollama'
    static_configs:
      - targets: ['ollama:11434']

EOF
    fi

    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
        cat >> "${prom_dir}/prometheus.yml" << 'EOF'
  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres:5432']

EOF
    fi

    # Grafana provisioning
    local grafana_dir="${CONFIG_DIR}/grafana"
    mkdir -p "${grafana_dir}/provisioning/datasources"
    mkdir -p "${grafana_dir}/provisioning/dashboards"

    cat > "${grafana_dir}/provisioning/datasources/prometheus.yml" << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
EOF

    cat > "${grafana_dir}/provisioning/dashboards/default.yml" << 'EOF'
apiVersion: 1

providers:
  - name: 'Default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF

    log_success "Monitoring configurations generated"
}

################################################################################
# DEPLOYMENT FUNCTIONS
################################################################################

create_directory_structure() {
    log_step "Creating Directory Structure"

    local dirs=(
        "$CONFIG_DIR"
        "$LOG_DIR"
        "$BACKUP_DIR"
    )

    if [[ "${CONFIG_VALUES[STORAGE_TYPE]}" == "bind-mounts" ]]; then
        [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]] && dirs+=("${CONFIG_VALUES[DATA_DIR]}/ollama")
        [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]] && dirs+=("${CONFIG_VALUES[DATA_DIR]}/webui")
        [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]] && dirs+=("${CONFIG_VALUES[DATA_DIR]}/n8n")
        [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]] && dirs+=("${CONFIG_VALUES[DATA_DIR]}/postgres")
        [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]] && dirs+=("${CONFIG_VALUES[DATA_DIR]}/redis")
        [[ "${CONFIG_VALUES[INSTALL_MONITORING]}" == "true" ]] && dirs+=("${CONFIG_VALUES[DATA_DIR]}/prometheus" "${CONFIG_VALUES[DATA_DIR]}/grafana")
    fi

    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_info "Created: $dir"
        fi
    done

    log_success "Directory structure created"
}

deploy_services() {
    log_step "Deploying Services"

    cd "$PROJECT_ROOT"

    log_info "Pulling Docker images..."
    docker compose pull

    log_info "Starting services..."
    docker compose up -d

    log_info "Waiting for services to be ready..."
    sleep 10

    # Check service health
    log_info "Checking service health..."
    docker compose ps

    log_success "Services deployed successfully"
}

post_installation_tasks() {
    log_step "Running Post-Installation Tasks"

    # Download Ollama models if configured
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]] && [[ "${CONFIG_VALUES[PREDOWNLOAD_MODELS]}" == "true" ]]; then
        log_info "Downloading Ollama models..."

        IFS=',' read -ra MODELS <<< "${CONFIG_VALUES[OLLAMA_MODELS]}"
        for model in "${MODELS[@]}"; do
            log_info "Pulling model: $model"
            docker exec "${CONFIG_VALUES[COMPOSE_PROJECT_NAME]}_ollama" ollama pull "$model" || log_warn "Failed to pull model: $model"
        done
    fi

    # Setup SSL if configured
    if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]] && [[ "${CONFIG_VALUES[SSL_METHOD]}" == "letsencrypt" ]]; then
        log_info "Setting up Let's Encrypt SSL certificates..."
        setup_letsencrypt
    fi

    # Configure UFW if enabled
    if [[ "${CONFIG_VALUES[ENABLE_UFW]}" == "true" ]]; then
        configure_firewall
    fi

    log_success "Post-installation tasks completed"
}

setup_letsencrypt() {
    if ! command -v certbot &> /dev/null; then
        log_info "Installing certbot..."
        sudo apt-get update
        sudo apt-get install -y certbot
    fi

    local domains=""
    [[ -n "${CONFIG_VALUES[WEBUI_DOMAIN]:-}" ]] && domains="$domains -d ${CONFIG_VALUES[WEBUI_DOMAIN]}"
    [[ -n "${CONFIG_VALUES[N8N_DOMAIN]:-}" ]] && domains="$domains -d ${CONFIG_VALUES[N8N_DOMAIN]}"
    [[ -n "${CONFIG_VALUES[GRAFANA_DOMAIN]:-}" ]] && domains="$domains -d ${CONFIG_VALUES[GRAFANA_DOMAIN]}"

    if [[ -n "$domains" ]]; then
        sudo certbot certonly --standalone \
            --non-interactive \
            --agree-tos \
            --email "${CONFIG_VALUES[SSL_EMAIL]}" \
            $domains

        # Copy certificates to nginx ssl directory
        local ssl_dir="${CONFIG_DIR}/nginx/ssl"
        mkdir -p "$ssl_dir"

        for domain in ${CONFIG_VALUES[WEBUI_DOMAIN]:-} ${CONFIG_VALUES[N8N_DOMAIN]:-} ${CONFIG_VALUES[GRAFANA_DOMAIN]:-}; do
            if [[ -n "$domain" ]]; then
                mkdir -p "${ssl_dir}/${domain}"
                sudo cp "/etc/letsencrypt/live/${domain}/fullchain.pem" "${ssl_dir}/${domain}/"
                sudo cp "/etc/letsencrypt/live/${domain}/privkey.pem" "${ssl_dir}/${domain}/"
                sudo chown -R $USER:$USER "${ssl_dir}/${domain}"
            fi
        done

        log_success "SSL certificates configured"
    fi
}

configure_firewall() {
    log_info "Configuring UFW firewall..."

    if ! command -v ufw &> /dev/null; then
        log_warn "UFW not installed, skipping firewall configuration"
        return 1
    fi

    # Allow SSH
    sudo ufw allow 22/tcp

    # Allow configured ports
    [[ -n "${CONFIG_VALUES[NGINX_HTTP_PORT]:-}" ]] && sudo ufw allow "${CONFIG_VALUES[NGINX_HTTP_PORT]}/tcp"
    [[ -n "${CONFIG_VALUES[NGINX_HTTPS_PORT]:-}" ]] && sudo ufw allow "${CONFIG_VALUES[NGINX_HTTPS_PORT]}/tcp"

    if [[ "${CONFIG_VALUES[INSTALL_NGINX]}" != "true" ]]; then
        [[ -n "${CONFIG_VALUES[WEBUI_PORT]:-}" ]] && sudo ufw allow "${CONFIG_VALUES[WEBUI_PORT]}/tcp"
        [[ -n "${CONFIG_VALUES[N8N_PORT]:-}" ]] && sudo ufw allow "${CONFIG_VALUES[N8N_PORT]}/tcp"
        [[ -n "${CONFIG_VALUES[OLLAMA_PORT]:-}" ]] && sudo ufw allow "${CONFIG_VALUES[OLLAMA_PORT]}/tcp"
    fi

    sudo ufw --force enable
    log_success "Firewall configured"
}

################################################################################
# HELPER SCRIPTS GENERATION
################################################################################

generate_helper_scripts() {
    log_step "Generating Helper Scripts"

    # Start script
    cat > "${SCRIPT_DIR}/start.sh" << 'EOF'
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"
echo "Starting AI Platform services..."
docker compose up -d

echo ""
echo "Waiting for services..."
sleep 5

echo ""
docker compose ps
EOF
    chmod +x "${SCRIPT_DIR}/start.sh"

    # Stop script
    cat > "${SCRIPT_DIR}/stop.sh" << 'EOF'
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"
echo "Stopping AI Platform services..."
docker compose down

echo "Services stopped."
EOF
    chmod +x "${SCRIPT_DIR}/stop.sh"

    # Restart script
    cat > "${SCRIPT_DIR}/restart.sh" << 'EOF'
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/stop.sh"
sleep 2
"$SCRIPT_DIR/start.sh"
EOF
    chmod +x "${SCRIPT_DIR}/restart.sh"

    # Status script
    cat > "${SCRIPT_DIR}/status.sh" << 'EOF'
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"
docker compose ps
EOF
    chmod +x "${SCRIPT_DIR}/status.sh"

    # Logs script
    cat > "${SCRIPT_DIR}/logs.sh" << 'EOF'
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

if [[ -n "$1" ]]; then
    docker compose logs -f "$1"
else
    docker compose logs -f
fi
EOF
    chmod +x "${SCRIPT_DIR}/logs.sh"

    # Backup script
    cat > "${SCRIPT_DIR}/backup.sh" << 'EOF'
#!/bin/bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${PROJECT_ROOT}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

source "${PROJECT_ROOT}/.env"

mkdir -p "$BACKUP_DIR"

echo "Creating backup: backup_${TIMESTAMP}"

# Backup Docker volumes or bind mounts
if [[ -d "${PROJECT_ROOT}/data" ]]; then
    tar -czf "${BACKUP_DIR}/data_${TIMESTAMP}.tar.gz" -C "${PROJECT_ROOT}" data
fi

# Backup database
if [[ "${INSTALL_POSTGRES}" == "true" ]]; then
    docker exec "${COMPOSE_PROJECT_NAME}_postgres" pg_dumpall -U "${POSTGRES_USER}" | \
        gzip > "${BACKUP_DIR}/postgres_${TIMESTAMP}.sql.gz"
fi

# Backup configuration
tar -czf "${BACKUP_DIR}/config_${TIMESTAMP}.tar.gz" -C "${PROJECT_ROOT}" config .env docker-compose.yml

echo "Backup completed: ${BACKUP_DIR}/backup_${TIMESTAMP}"

# Cleanup old backups
find "$BACKUP_DIR" -type f -name "*.tar.gz" -mtime +30 -delete
find "$BACKUP_DIR" -type f -name "*.sql.gz" -mtime +30 -delete

echo "Old backups cleaned up (kept last 30 days)"
EOF
    chmod +x "${SCRIPT_DIR}/backup.sh"

    # Update script
    cat > "${SCRIPT_DIR}/update.sh" << 'EOF'
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "Creating backup before update..."
"${SCRIPT_DIR}/backup.sh"

echo "Pulling latest images..."
docker compose pull

echo "Restarting services..."
docker compose up -d

echo "Update completed!"
docker compose ps
EOF
    chmod +x "${SCRIPT_DIR}/update.sh"

    log_success "Helper scripts generated in ${SCRIPT_DIR}/"
}

################################################################################
# SUMMARY AND COMPLETION
################################################################################

display_summary() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "          AI PLATFORM INSTALLATION COMPLETED!"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "${BOLD}Access Information:${NC}"

    if [[ "${CONFIG_VALUES[INSTALL_WEBUI]}" == "true" ]]; then
        if [[ -n "${CONFIG_VALUES[WEBUI_DOMAIN]:-}" ]]; then
            echo "  WebUI: https://${CONFIG_VALUES[WEBUI_DOMAIN]}"
        else
            echo "  WebUI: http://localhost:${CONFIG_VALUES[WEBUI_PORT]}"
        fi
    fi

    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        if [[ -n "${CONFIG_VALUES[N8N_DOMAIN]:-}" ]]; then
            echo "  n8n: https://${CONFIG_VALUES[N8N_DOMAIN]}"
        else
            echo "  n8n: http://localhost:${CONFIG_VALUES[N8N_PORT]}"
        fi
        echo "    Email: ${CONFIG_VALUES[N8N_USER_EMAIL]}"
    fi

    if [[ "${CONFIG_VALUES[INSTALL_MONITORING]}" == "true" ]]; then
        echo "  Grafana: http://localhost:${CONFIG_VALUES[GRAFANA_PORT]}"
        echo "    User: ${CONFIG_VALUES[GRAFANA_ADMIN_USER]}"
    fi

    echo ""
    echo "${BOLD}Helper Scripts:${NC}"
    echo "  Start services:   ./scripts/start.sh"
    echo "  Stop services:    ./scripts/stop.sh"
    echo "  Restart services: ./scripts/restart.sh"
    echo "  View status:      ./scripts/status.sh"
    echo "  View logs:        ./scripts/logs.sh [service]"
    echo "  Create backup:    ./scripts/backup.sh"
    echo "  Update platform:  ./scripts/update.sh"

    echo ""
    echo "${BOLD}Important Files:${NC}"
    echo "  Configuration: ${PROJECT_ROOT}/.env"
    echo "  Docker Compose: ${PROJECT_ROOT}/docker-compose.yml"
    echo "  Logs: ${LOG_DIR}/"
    echo "  Backups: ${BACKUP_DIR}/"

    echo ""
    echo "${BOLD}Next Steps:${NC}"
    echo "  1. Review service status: docker compose ps"
    echo "  2. Check logs: docker compose logs -f"
    echo "  3. Access services using URLs above"

    if [[ "${CONFIG_VALUES[PREDOWNLOAD_MODELS]}" == "true" ]]; then
        echo "  4. Wait for models to finish downloading (check logs)"
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "Documentation: ${PROJECT_ROOT}/README.md"
    echo "Support: https://github.com/yourusername/aiplatform/issues"
    echo ""
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "        AI PLATFORM AUTOMATED INSTALLATION"
    echo "        Version: $VERSION"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""

    # Create log directory
    mkdir -p "$LOG_DIR"

    # System checks
    check_system_requirements

    if ! check_docker; then
        if prompt_yes_no "Docker not found or not properly configured. Install Docker?" "y"; then
            install_docker
        else
            log_error "Docker is required. Exiting."
            exit 1
        fi
    fi

    # Collect all configuration
    step_01_installation_type
    step_02_project_info
    step_03_stack_selection
    step_04_service_ports
    step_05_storage_config
    step_06_database_config
    step_07_proxy_config
    step_08_backup_config
    step_09_logging_config
    step_10_resource_limits
    step_11_network_config
    step_12_timezone_config
    step_13_auth_config
    step_14_model_selection
    step_15_model_settings
    step_16_webui_features
    step_17_n8n_config
    step_18_integration_apis
    step_19_email_config
    step_20_webhook_config
    step_21_cors_config
    step_22_cache_config
    step_23_session_config
    step_24_security_hardening
    step_25_health_checks
    step_26_performance_tuning
    step_27_final_review

    # Generate configurations
    create_directory_structure
    generate_env_file
    generate_docker_compose
    generate_nginx_config
    generate_monitoring_configs
    generate_helper_scripts

    # Deploy
    deploy_services
    post_installation_tasks

    # Summary
    display_summary

    log_success "Installation completed at $(date)"
}

# Error handling
trap 'log_error "Installation failed at line $LINENO. Check log: $LOG_FILE"' ERR

# Run main
main "$@"
