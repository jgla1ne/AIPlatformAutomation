#!/bin/bash
################################################################################
# AI Platform Automation - System Setup Script
# Part 1/4: Foundation - Constants, Logging, and Core Utilities
################################################################################

set -euo pipefail
IFS=$'\n\t'

#==============================================================================
# SCRIPT METADATA
#==============================================================================
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_NAME="AI Platform System Setup"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

#==============================================================================
# CONFIGURATION PATHS
#==============================================================================
readonly CONFIG_DIR="${PROJECT_ROOT}/config"
readonly ENV_FILE="${CONFIG_DIR}/.env"
readonly DOCKER_COMPOSE_FILE="${CONFIG_DIR}/docker-compose.yml"
readonly BACKUP_DIR="${PROJECT_ROOT}/backups"
readonly LOG_DIR="${PROJECT_ROOT}/logs"
readonly LOG_FILE="${LOG_DIR}/setup_${TIMESTAMP}.log"

#==============================================================================
# DEFAULT CONFIGURATION VALUES
#==============================================================================
declare -gA CONFIG_VALUES=(
    # Environment
    [ENVIRONMENT]="production"
    [COMPOSE_PROJECT_NAME]="aiplatform"
    [BASE_DOMAIN]="localhost"
    
    # Core Services
    [INSTALL_OLLAMA]="true"
    [INSTALL_OPEN_WEBUI]="true"
    [INSTALL_N8N]="true"
    [INSTALL_NGINX]="true"
    [INSTALL_POSTGRES]="true"
    [INSTALL_REDIS]="true"
    
    # Optional Services
    [INSTALL_PROMETHEUS]="false"
    [INSTALL_GRAFANA]="false"
    [INSTALL_PORTAINER]="false"
    [INSTALL_WATCHTOWER]="false"
    
    # Ports (defaults)
    [OLLAMA_PORT]="11434"
    [OPEN_WEBUI_PORT]="3000"
    [N8N_PORT]="5678"
    [NGINX_HTTP_PORT]="80"
    [NGINX_HTTPS_PORT]="443"
    [POSTGRES_PORT]="5432"
    [REDIS_PORT]="6379"
    [PROMETHEUS_PORT]="9090"
    [GRAFANA_PORT]="3001"
    [PORTAINER_PORT]="9000"
    
    # Storage
    [DATA_ROOT]="/opt/aiplatform"
    [OLLAMA_MODELS_DIR]="/opt/aiplatform/ollama/models"
    [BACKUP_ENABLED]="true"
    [BACKUP_RETENTION_DAYS]="30"
    
    # Resource Limits
    [OLLAMA_MAX_MEMORY]="8g"
    [N8N_MAX_MEMORY]="2g"
    [POSTGRES_MAX_MEMORY]="2g"
    [ENABLE_GPU]="false"
    
    # Security
    [ENABLE_SSL]="false"
    [SSL_EMAIL]=""
    [FORCE_HTTPS]="false"
    
    # Timezone
    [TIMEZONE]="UTC"
)

#==============================================================================
# COLOR CODES FOR OUTPUT
#==============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

#==============================================================================
# LOGGING FUNCTIONS
#==============================================================================

setup_logging() {
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"
    log_info "Logging initialized: $LOG_FILE"
}

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    log "SUCCESS" "$@"
    echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
    log "WARNING" "$@"
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    log "ERROR" "$@"
    echo -e "${RED}✗${NC} $*" >&2
}

log_step() {
    log "STEP" "$@"
    echo -e "${CYAN}▶${NC} ${BOLD}$*${NC}"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log "DEBUG" "$@"
        echo -e "${MAGENTA}[DEBUG]${NC} $*"
    fi
}

#==============================================================================
# UI/DISPLAY FUNCTIONS
#==============================================================================

print_header() {
    clear
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                                                                ║"
    echo "║           AI PLATFORM AUTOMATION - SYSTEM SETUP                ║"
    echo "║                                                                ║"
    echo "║  Automated installation and configuration for:                 ║"
    echo "║  • Ollama (LLM Runtime)                                        ║"
    echo "║  • Open WebUI (Chat Interface)                                 ║"
    echo "║  • n8n (Workflow Automation)                                   ║"
    echo "║  • Nginx (Reverse Proxy)                                       ║"
    echo "║  • PostgreSQL + Redis (Data Layer)                             ║"
    echo "║  • Prometheus + Grafana (Monitoring)                           ║"
    echo "║                                                                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo
    echo "Version: ${SCRIPT_VERSION}"
    echo "Documentation: https://github.com/jgla1ne/AIPlatformAutomation"
    echo
}

print_step_header() {
    local step_num=$1
    local step_title=$2
    echo
    echo "┌─────────────────────────────────────────────────────────────┐"
    printf "│ ${BOLD}Step %2d/27:${NC} %-48s │\n" "$step_num" "$step_title"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo
}

print_section_break() {
    echo
    echo "================================================================"
    echo
}

print_success_box() {
    local message=$1
    echo
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  ${GREEN}✓ SUCCESS${NC}                                                     ║"
    echo "╠════════════════════════════════════════════════════════════════╣"
    printf "║  %-60s  ║\n" "$message"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo
}

print_error_box() {
    local message=$1
    echo
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  ${RED}✗ ERROR${NC}                                                       ║"
    echo "╠════════════════════════════════════════════════════════════════╣"
    printf "║  %-60s  ║\n" "$message"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo
}

print_warning_box() {
    local message=$1
    echo
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  ${YELLOW}⚠ WARNING${NC}                                                    ║"
    echo "╠════════════════════════════════════════════════════════════════╣"
    printf "║  %-60s  ║\n" "$message"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo
}

#==============================================================================
# USER INPUT FUNCTIONS
#==============================================================================

prompt_with_default() {
    local prompt=$1
    local default=$2
    local response
    
    read -rp "$(echo -e "${CYAN}?${NC} ${prompt} [${default}]: ")" response
    echo "${response:-$default}"
}

prompt_yes_no() {
    local prompt=$1
    local default=${2:-n}
    local response
    
    while true; do
        if [[ "$default" == "y" ]]; then
            read -rp "$(echo -e "${CYAN}?${NC} ${prompt} [Y/n]: ")" response
            response=${response:-y}
        else
            read -rp "$(echo -e "${CYAN}?${NC} ${prompt} [y/N]: ")" response
            response=${response:-n}
        fi
        
        case "${response,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) log_warning "Please answer yes or no." ;;
        esac
    done
}

prompt_password() {
    local prompt=$1
    local password
    local password_confirm
    
    while true; do
        read -rsp "$(echo -e "${CYAN}?${NC} ${prompt}: ")" password
        echo
        read -rsp "$(echo -e "${CYAN}?${NC} Confirm password: ")" password_confirm
        echo
        
        if [[ "$password" == "$password_confirm" ]]; then
            if [[ ${#password} -ge 8 ]]; then
                echo "$password"
                return 0
            else
                log_warning "Password must be at least 8 characters"
            fi
        else
            log_warning "Passwords do not match"
        fi
    done
}

prompt_choice() {
    local prompt=$1
    shift
    local options=("$@")
    local choice
    
    echo -e "${CYAN}?${NC} ${prompt}"
    for i in "${!options[@]}"; do
        echo "  $((i+1))) ${options[$i]}"
    done
    
    while true; do
        read -rp "Enter choice [1-${#options[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#options[@]})); then
            echo "${options[$((choice-1))]}"
            return 0
        else
            log_warning "Invalid choice. Please select 1-${#options[@]}"
        fi
    done
}

#==============================================================================
# UTILITY FUNCTIONS
#==============================================================================

generate_random_password() {
    local length=${1:-32}
    LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c "$length"
}

generate_random_string() {
    local length=${1:-16}
    LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
}

is_port_available() {
    local port=$1
    ! netstat -tuln 2>/dev/null | grep -q ":${port} " && \
    ! ss -tuln 2>/dev/null | grep -q ":${port} "
}

is_valid_email() {
    local email=$1
    [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

is_valid_domain() {
    local domain=$1
    [[ "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

is_valid_ip() {
    local ip=$1
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

check_disk_space() {
    local required_gb=${1:-20}
    local available_gb=$(df -BG "$PROJECT_ROOT" | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if ((available_gb < required_gb)); then
        log_error "Insufficient disk space. Required: ${required_gb}GB, Available: ${available_gb}GB"
        return 1
    fi
    return 0
}

check_memory() {
    local required_gb=${1:-4}
    local available_gb=$(free -g | awk 'NR==2 {print $7}')
    
    if ((available_gb < required_gb)); then
        log_warning "Low memory. Required: ${required_gb}GB, Available: ${available_gb}GB"
        return 1
    fi
    return 0
}

create_directory_structure() {
    log_info "Creating directory structure..."
    
    local dirs=(
        "$CONFIG_DIR"
        "$BACKUP_DIR"
        "$LOG_DIR"
        "${CONFIG_VALUES[DATA_ROOT]}"
        "${CONFIG_VALUES[DATA_ROOT]}/ollama"
        "${CONFIG_VALUES[DATA_ROOT]}/open-webui"
        "${CONFIG_VALUES[DATA_ROOT]}/n8n"
        "${CONFIG_VALUES[DATA_ROOT]}/postgres"
        "${CONFIG_VALUES[DATA_ROOT]}/redis"
        "${CONFIG_VALUES[DATA_ROOT]}/nginx/conf.d"
        "${CONFIG_VALUES[DATA_ROOT]}/nginx/ssl"
        "${CONFIG_VALUES[DATA_ROOT]}/prometheus"
        "${CONFIG_VALUES[DATA_ROOT]}/grafana"
    )
    
    for dir in "${dirs[@]}"; do
        if ! mkdir -p "$dir"; then
            log_error "Failed to create directory: $dir"
            return 1
        fi
    done
    
    log_success "Directory structure created"
    return 0
}

#==============================================================================
# VALIDATION FUNCTIONS
#==============================================================================

validate_prerequisites() {
    log_step "Validating prerequisites..."
    
    local missing_tools=()
    
    # Check required commands
    local required_commands=(
        "docker:Docker"
        "docker-compose:Docker Compose"
        "curl:cURL"
        "jq:jq"
        "openssl:OpenSSL"
    )
    
    for cmd_info in "${required_commands[@]}"; do
        IFS=: read -r cmd name <<< "$cmd_info"
        if ! command -v "$cmd" &>/dev/null; then
            missing_tools+=("$name")
            log_error "$name is not installed"
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_error_box "Missing required tools: ${missing_tools[*]}"
        log_error "Please install missing tools and run again"
        return 1
    fi
    
    # Check Docker daemon
    if ! docker ps &>/dev/null; then
        log_error "Docker daemon is not running"
        return 1
    fi
    
    # Check Docker Compose version
    local compose_version=$(docker-compose version --short 2>/dev/null || echo "0")
    log_info "Docker Compose version: $compose_version"
    
    # Check user permissions
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should NOT be run as root"
        log_info "Please run as regular user with docker group membership"
        return 1
    fi
    
    # Check docker group membership
    if ! groups | grep -q docker; then
        log_warning "User not in docker group"
        log_info "Run: sudo usermod -aG docker $USER && newgrp docker"
    fi
    
    # Check disk space
    if ! check_disk_space 20; then
        return 1
    fi
    
    # Check memory
    check_memory 4 || log_warning "System has limited memory"
    
    log_success "All prerequisites validated"
    return 0
}

validate_configuration() {
    log_step "Validating configuration..."
    
    local errors=0
    
    # Validate ports
    for key in "${!CONFIG_VALUES[@]}"; do
        if [[ "$key" =~ _PORT$ ]]; then
            local port="${CONFIG_VALUES[$key]}"
            if ! [[ "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
                log_error "Invalid port for $key: $port"
                ((errors++))
            fi
        fi
    done
    
    # Validate email if SSL is enabled
    if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]]; then
        if ! is_valid_email "${CONFIG_VALUES[SSL_EMAIL]:-}"; then
            log_error "Invalid email address for SSL"
            ((errors++))
        fi
    fi
    
    # Validate domain
    if [[ "${CONFIG_VALUES[BASE_DOMAIN]}" != "localhost" ]]; then
        if ! is_valid_domain "${CONFIG_VALUES[BASE_DOMAIN]}"; then
            log_error "Invalid domain: ${CONFIG_VALUES[BASE_DOMAIN]}"
            ((errors++))
        fi
    fi
    
    if ((errors > 0)); then
        log_error "Configuration validation failed with $errors error(s)"
        return 1
    fi
    
    log_success "Configuration validated"
    return 0
}

#==============================================================================
# END OF PART 1/4
#==============================================================================
#
#!/bin/bash
################################################################################
# AI Platform Automation - System Setup Script
# Part 2/4: Configuration Wizard Steps 1-10
################################################################################

#==============================================================================
# STEP 1: WELCOME AND OVERVIEW
#==============================================================================

step_01_welcome() {
    print_step_header 1 "Welcome and Overview"
    
    log_info "Starting AI Platform setup wizard"
    
    cat << 'EOF'
Welcome to the AI Platform Automation setup wizard!

This wizard will guide you through configuring:
  
  CORE SERVICES:
  • Ollama - Local LLM runtime for AI models
  • Open WebUI - Modern chat interface for Ollama
  • n8n - Workflow automation platform
  • Nginx - Reverse proxy and SSL termination
  
  DATA LAYER:
  • PostgreSQL - Primary database
  • Redis - Caching and session storage
  
  MONITORING (Optional):
  • Prometheus - Metrics collection
  • Grafana - Visualization dashboards
  • Portainer - Docker management UI
  
  FEATURES:
  • Automated SSL with Let's Encrypt
  • Backup and restore functionality
  • Resource monitoring and alerts
  • Multi-model support
  • API key management

The wizard takes approximately 5-10 minutes to complete.
All services will be containerized using Docker Compose.

EOF

    log_info "System Information:"
    log_info "  OS: $(uname -s) $(uname -r)"
    log_info "  User: $USER"
    log_info "  Project Root: $PROJECT_ROOT"
    log_info "  Data Root: ${CONFIG_VALUES[DATA_ROOT]}"
    
    echo
    if ! prompt_yes_no "Ready to begin setup?" "y"; then
        log_warning "Setup cancelled by user"
        exit 0
    fi
    
    log_success "Step 1 completed: Welcome acknowledged"
}

#==============================================================================
# STEP 2: ENVIRONMENT SELECTION
#==============================================================================

step_02_environment() {
    print_step_header 2 "Environment Selection"
    
    cat << 'EOF'
Select your deployment environment:

  1) Production  - Full security, optimized performance
  2) Development - Debug logging, relaxed security
  3) Testing     - Isolated environment, mock services

EOF

    local env=$(prompt_choice "Select environment:" "production" "development" "testing")
    CONFIG_VALUES[ENVIRONMENT]="$env"
    
    log_info "Environment selected: $env"
    
    # Set environment-specific defaults
    case "$env" in
        production)
            CONFIG_VALUES[DEBUG]="false"
            CONFIG_VALUES[LOG_LEVEL]="info"
            CONFIG_VALUES[ENABLE_SSL]="true"
            ;;
        development)
            CONFIG_VALUES[DEBUG]="true"
            CONFIG_VALUES[LOG_LEVEL]="debug"
            CONFIG_VALUES[ENABLE_SSL]="false"
            ;;
        testing)
            CONFIG_VALUES[DEBUG]="true"
            CONFIG_VALUES[LOG_LEVEL]="debug"
            CONFIG_VALUES[ENABLE_SSL]="false"
            CONFIG_VALUES[COMPOSE_PROJECT_NAME]="aiplatform-test"
            ;;
    esac
    
    # Project name
    local project_name=$(prompt_with_default "Project name" "${CONFIG_VALUES[COMPOSE_PROJECT_NAME]}")
    CONFIG_VALUES[COMPOSE_PROJECT_NAME]="$project_name"
    
    log_success "Step 2 completed: Environment configured as $env"
}

#==============================================================================
# STEP 3: SERVICE SELECTION
#==============================================================================

step_03_services() {
    print_step_header 3 "Service Selection"
    
    cat << 'EOF'
Select which services to install:

CORE SERVICES (Required):
EOF

    # Core services with dependencies
    if prompt_yes_no "Install Ollama (LLM Runtime)?" "y"; then
        CONFIG_VALUES[INSTALL_OLLAMA]="true"
        log_info "Ollama will be installed"
    else
        CONFIG_VALUES[INSTALL_OLLAMA]="false"
        log_warning "Ollama disabled - AI features will not work"
    fi
    
    if prompt_yes_no "Install Open WebUI (Chat Interface)?" "y"; then
        CONFIG_VALUES[INSTALL_OPEN_WEBUI]="true"
        log_info "Open WebUI will be installed"
        
        if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "false" ]]; then
            log_warning "Open WebUI requires Ollama - enabling Ollama"
            CONFIG_VALUES[INSTALL_OLLAMA]="true"
        fi
    else
        CONFIG_VALUES[INSTALL_OPEN_WEBUI]="false"
    fi
    
    if prompt_yes_no "Install n8n (Workflow Automation)?" "y"; then
        CONFIG_VALUES[INSTALL_N8N]="true"
        log_info "n8n will be installed"
    else
        CONFIG_VALUES[INSTALL_N8N]="false"
    fi
    
    echo
    echo "DATA SERVICES:"
    
    if prompt_yes_no "Install PostgreSQL (Database)?" "y"; then
        CONFIG_VALUES[INSTALL_POSTGRES]="true"
        log_info "PostgreSQL will be installed"
    else
        CONFIG_VALUES[INSTALL_POSTGRES]="false"
        if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
            log_warning "n8n requires PostgreSQL - enabling PostgreSQL"
            CONFIG_VALUES[INSTALL_POSTGRES]="true"
        fi
    fi
    
    if prompt_yes_no "Install Redis (Cache/Sessions)?" "y"; then
        CONFIG_VALUES[INSTALL_REDIS]="true"
        log_info "Redis will be installed"
    else
        CONFIG_VALUES[INSTALL_REDIS]="false"
    fi
    
    echo
    echo "INFRASTRUCTURE:"
    
    if prompt_yes_no "Install Nginx (Reverse Proxy)?" "y"; then
        CONFIG_VALUES[INSTALL_NGINX]="true"
        log_info "Nginx will be installed"
    else
        CONFIG_VALUES[INSTALL_NGINX]="false"
    fi
    
    echo
    echo "MONITORING (Optional):"
    
    if prompt_yes_no "Install Prometheus + Grafana?" "n"; then
        CONFIG_VALUES[INSTALL_PROMETHEUS]="true"
        CONFIG_VALUES[INSTALL_GRAFANA]="true"
        log_info "Monitoring stack will be installed"
    else
        CONFIG_VALUES[INSTALL_PROMETHEUS]="false"
        CONFIG_VALUES[INSTALL_GRAFANA]="false"
    fi
    
    if prompt_yes_no "Install Portainer (Docker UI)?" "n"; then
        CONFIG_VALUES[INSTALL_PORTAINER]="true"
        log_info "Portainer will be installed"
    else
        CONFIG_VALUES[INSTALL_PORTAINER]="false"
    fi
    
    if prompt_yes_no "Install Watchtower (Auto-updates)?" "n"; then
        CONFIG_VALUES[INSTALL_WATCHTOWER]="true"
        log_info "Watchtower will be installed"
    else
        CONFIG_VALUES[INSTALL_WATCHTOWER]="false"
    fi
    
    log_success "Step 3 completed: Services selected"
}

#==============================================================================
# STEP 4: PORT CONFIGURATION
#==============================================================================

step_04_ports() {
    print_step_header 4 "Port Configuration"
    
    cat << 'EOF'
Configure network ports for services.
Press Enter to accept defaults.

EOF

    # Ollama
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        local ollama_port=$(prompt_with_default "Ollama API port" "${CONFIG_VALUES[OLLAMA_PORT]}")
        if is_port_available "$ollama_port"; then
            CONFIG_VALUES[OLLAMA_PORT]="$ollama_port"
        else
            log_warning "Port $ollama_port is in use, using default ${CONFIG_VALUES[OLLAMA_PORT]}"
        fi
    fi
    
    # Open WebUI
    if [[ "${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}" == "true" ]]; then
        local webui_port=$(prompt_with_default "Open WebUI port" "${CONFIG_VALUES[OPEN_WEBUI_PORT]}")
        if is_port_available "$webui_port"; then
            CONFIG_VALUES[OPEN_WEBUI_PORT]="$webui_port"
        else
            log_warning "Port $webui_port is in use, using default ${CONFIG_VALUES[OPEN_WEBUI_PORT]}"
        fi
    fi
    
    # n8n
    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        local n8n_port=$(prompt_with_default "n8n port" "${CONFIG_VALUES[N8N_PORT]}")
        if is_port_available "$n8n_port"; then
            CONFIG_VALUES[N8N_PORT]="$n8n_port"
        else
            log_warning "Port $n8n_port is in use, using default ${CONFIG_VALUES[N8N_PORT]}"
        fi
    fi
    
    # Nginx
    if [[ "${CONFIG_VALUES[INSTALL_NGINX]}" == "true" ]]; then
        local http_port=$(prompt_with_default "Nginx HTTP port" "${CONFIG_VALUES[NGINX_HTTP_PORT]}")
        local https_port=$(prompt_with_default "Nginx HTTPS port" "${CONFIG_VALUES[NGINX_HTTPS_PORT]}")
        
        if is_port_available "$http_port"; then
            CONFIG_VALUES[NGINX_HTTP_PORT]="$http_port"
        else
            log_warning "Port $http_port is in use"
        fi
        
        if is_port_available "$https_port"; then
            CONFIG_VALUES[NGINX_HTTPS_PORT]="$https_port"
        else
            log_warning "Port $https_port is in use"
        fi
    fi
    
    # PostgreSQL
    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
        local pg_port=$(prompt_with_default "PostgreSQL port" "${CONFIG_VALUES[POSTGRES_PORT]}")
        if is_port_available "$pg_port"; then
            CONFIG_VALUES[POSTGRES_PORT]="$pg_port"
        else
            log_warning "Port $pg_port is in use"
        fi
    fi
    
    # Redis
    if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
        local redis_port=$(prompt_with_default "Redis port" "${CONFIG_VALUES[REDIS_PORT]}")
        if is_port_available "$redis_port"; then
            CONFIG_VALUES[REDIS_PORT]="$redis_port"
        else
            log_warning "Port $redis_port is in use"
        fi
    fi
    
    # Monitoring
    if [[ "${CONFIG_VALUES[INSTALL_PROMETHEUS]}" == "true" ]]; then
        local prom_port=$(prompt_with_default "Prometheus port" "${CONFIG_VALUES[PROMETHEUS_PORT]}")
        CONFIG_VALUES[PROMETHEUS_PORT]="$prom_port"
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_GRAFANA]}" == "true" ]]; then
        local grafana_port=$(prompt_with_default "Grafana port" "${CONFIG_VALUES[GRAFANA_PORT]}")
        CONFIG_VALUES[GRAFANA_PORT]="$grafana_port"
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_PORTAINER]}" == "true" ]]; then
        local portainer_port=$(prompt_with_default "Portainer port" "${CONFIG_VALUES[PORTAINER_PORT]}")
        CONFIG_VALUES[PORTAINER_PORT]="$portainer_port"
    fi
    
    log_success "Step 4 completed: Ports configured"
}

#==============================================================================
# STEP 5: STORAGE CONFIGURATION
#==============================================================================

step_05_storage() {
    print_step_header 5 "Storage Configuration"
    
    cat << 'EOF'
Configure storage paths and volumes.

All data will be stored in a centralized location for easy backup.

EOF

    # Data root directory
    local data_root=$(prompt_with_default "Data root directory" "${CONFIG_VALUES[DATA_ROOT]}")
    CONFIG_VALUES[DATA_ROOT]="$data_root"
    
    # Ollama models directory
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        local models_dir=$(prompt_with_default "Ollama models directory" "${data_root}/ollama/models")
        CONFIG_VALUES[OLLAMA_MODELS_DIR]="$models_dir"
        
        log_info "Estimated space for models: 10-50GB depending on selection"
    fi
    
    # Check available space
    log_info "Checking disk space..."
    local available_space=$(df -BG "$data_root" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//' || echo "unknown")
    
    if [[ "$available_space" != "unknown" ]]; then
        log_info "Available space: ${available_space}GB"
        
        if ((available_space < 20)); then
            log_warning "Low disk space detected"
            if ! prompt_yes_no "Continue anyway?" "n"; then
                log_error "Setup cancelled due to insufficient disk space"
                exit 1
            fi
        fi
    fi
    
    # Backup configuration
    if prompt_yes_no "Enable automated backups?" "y"; then
        CONFIG_VALUES[BACKUP_ENABLED]="true"
        
        local backup_retention=$(prompt_with_default "Backup retention (days)" "${CONFIG_VALUES[BACKUP_RETENTION_DAYS]}")
        CONFIG_VALUES[BACKUP_RETENTION_DAYS]="$backup_retention"
        
        local backup_schedule=$(prompt_choice "Backup schedule:" "Daily at 2 AM" "Weekly on Sunday" "Custom cron")
        case "$backup_schedule" in
            "Daily at 2 AM")
                CONFIG_VALUES[BACKUP_SCHEDULE]="0 2 * * *"
                ;;
            "Weekly on Sunday")
                CONFIG_VALUES[BACKUP_SCHEDULE]="0 2 * * 0"
                ;;
            "Custom cron")
                read -rp "Enter cron expression: " custom_cron
                CONFIG_VALUES[BACKUP_SCHEDULE]="$custom_cron"
                ;;
        esac
        
        log_info "Backups enabled: ${CONFIG_VALUES[BACKUP_SCHEDULE]}"
    else
        CONFIG_VALUES[BACKUP_ENABLED]="false"
    fi
    
    log_success "Step 5 completed: Storage configured"
}

#==============================================================================
# STEP 6: DATABASE CONFIGURATION
#==============================================================================

step_06_database() {
    print_step_header 6 "Database Configuration"
    
    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" != "true" ]]; then
        log_info "PostgreSQL not selected, skipping database configuration"
        return 0
    fi
    
    cat << 'EOF'
Configure PostgreSQL database settings.

Secure passwords will be generated automatically.
You can customize them if needed.

EOF

    # PostgreSQL credentials
    local pg_user=$(prompt_with_default "PostgreSQL username" "aiplatform")
    CONFIG_VALUES[POSTGRES_USER]="$pg_user"
    
    local pg_db=$(prompt_with_default "PostgreSQL database name" "aiplatform")
    CONFIG_VALUES[POSTGRES_DB]="$pg_db"
    
    if prompt_yes_no "Generate random PostgreSQL password?" "y"; then
        CONFIG_VALUES[POSTGRES_PASSWORD]="$(generate_random_password 32)"
        log_info "Random password generated"
    else
        CONFIG_VALUES[POSTGRES_PASSWORD]="$(prompt_password "Enter PostgreSQL password")"
    fi
    
    # Additional databases for services
    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        CONFIG_VALUES[N8N_DB_NAME]="n8n"
        log_info "n8n database will be created: n8n"
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}" == "true" ]]; then
        CONFIG_VALUES[OPEN_WEBUI_DB_NAME]="openwebui"
        log_info "Open WebUI database will be created: openwebui"
    fi
    
    # PostgreSQL performance tuning
    local available_memory=$(free -g | awk 'NR==2 {print $2}')
    local pg_memory=$((available_memory / 4))
    
    if ((pg_memory > 4)); then
        pg_memory=4
    fi
    
    CONFIG_VALUES[POSTGRES_MAX_MEMORY]="${pg_memory}g"
    log_info "PostgreSQL memory limit: ${pg_memory}GB"
    
    log_success "Step 6 completed: Database configured"
}

#==============================================================================
# STEP 7: REVERSE PROXY CONFIGURATION
#==============================================================================

step_07_proxy() {
    print_step_header 7 "Reverse Proxy Configuration"
    
    if [[ "${CONFIG_VALUES[INSTALL_NGINX]}" != "true" ]]; then
        log_info "Nginx not selected, skipping proxy configuration"
        return 0
    fi
    
    cat << 'EOF'
Configure Nginx reverse proxy and domain settings.

You can use:
  • localhost (default, no SSL)
  • IP address (your server IP)
  • Domain name (requires DNS configuration)

EOF

    # Domain configuration
    local base_domain=$(prompt_with_default "Base domain or IP" "${CONFIG_VALUES[BASE_DOMAIN]}")
    CONFIG_VALUES[BASE_DOMAIN]="$base_domain"
    
    # Service subdomains
    if [[ "$base_domain" != "localhost" ]]; then
        if prompt_yes_no "Use subdomains for services?" "y"; then
            CONFIG_VALUES[USE_SUBDOMAINS]="true"
            
            local ollama_subdomain=$(prompt_with_default "Ollama subdomain" "ollama")
            CONFIG_VALUES[OLLAMA_SUBDOMAIN]="$ollama_subdomain"
            CONFIG_VALUES[OLLAMA_URL]="https://${ollama_subdomain}.${base_domain}"
            
            local webui_subdomain=$(prompt_with_default "Open WebUI subdomain" "chat")
            CONFIG_VALUES[WEBUI_SUBDOMAIN]="$webui_subdomain"
            CONFIG_VALUES[WEBUI_URL]="https://${webui_subdomain}.${base_domain}"
            
            if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
                local n8n_subdomain=$(prompt_with_default "n8n subdomain" "n8n")
                CONFIG_VALUES[N8N_SUBDOMAIN]="$n8n_subdomain"
                CONFIG_VALUES[N8N_URL]="https://${n8n_subdomain}.${base_domain}"
            fi
        else
            CONFIG_VALUES[USE_SUBDOMAINS]="false"
            CONFIG_VALUES[OLLAMA_URL]="https://${base_domain}:${CONFIG_VALUES[OLLAMA_PORT]}"
            CONFIG_VALUES[WEBUI_URL]="https://${base_domain}:${CONFIG_VALUES[OPEN_WEBUI_PORT]}"
            CONFIG_VALUES[N8N_URL]="https://${base_domain}:${CONFIG_VALUES[N8N_PORT]}"
        fi
    else
        CONFIG_VALUES[USE_SUBDOMAINS]="false"
        CONFIG_VALUES[OLLAMA_URL]="http://localhost:${CONFIG_VALUES[OLLAMA_PORT]}"
        CONFIG_VALUES[WEBUI_URL]="http://localhost:${CONFIG_VALUES[OPEN_WEBUI_PORT]}"
        CONFIG_VALUES[N8N_URL]="http://localhost:${CONFIG_VALUES[N8N_PORT]}"
    fi
    
    log_success "Step 7 completed: Proxy configured"
}

#==============================================================================
# STEP 8: BACKUP AND RESTORE
#==============================================================================

step_08_backup() {
    print_step_header 8 "Backup and Restore Configuration"
    
    if [[ "${CONFIG_VALUES[BACKUP_ENABLED]}" != "true" ]]; then
        log_info "Backups disabled, skipping backup configuration"
        return 0
    fi
    
    cat << 'EOF'
Configure backup settings.

Backups will include:
  • All configuration files
  • PostgreSQL databases
  • Redis data
  • Ollama models (optional)
  • Application data

EOF

    # Backup location
    local backup_dir=$(prompt_with_default "Backup directory" "$BACKUP_DIR")
    CONFIG_VALUES[BACKUP_DIR]="$backup_dir"
    
    # What to backup
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        if prompt_yes_no "Include Ollama models in backups? (requires significant space)" "n"; then
            CONFIG_VALUES[BACKUP_OLLAMA_MODELS]="true"
        else
            CONFIG_VALUES[BACKUP_OLLAMA_MODELS]="false"
        fi
    fi
    
    # Compression
    if prompt_yes_no "Compress backups?" "y"; then
        CONFIG_VALUES[BACKUP_COMPRESSION]="true"
        local compression_level=$(prompt_choice "Compression level:" "Fast (1)" "Balanced (6)" "Best (9)")
        case "$compression_level" in
            "Fast (1)") CONFIG_VALUES[BACKUP_COMPRESSION_LEVEL]="1" ;;
            "Balanced (6)") CONFIG_VALUES[BACKUP_COMPRESSION_LEVEL]="6" ;;
            "Best (9)") CONFIG_VALUES[BACKUP_COMPRESSION_LEVEL]="9" ;;
        esac
    else
        CONFIG_VALUES[BACKUP_COMPRESSION]="false"
    fi
    
    # Remote backup
    if prompt_yes_no "Configure remote backup location?" "n"; then
        CONFIG_VALUES[REMOTE_BACKUP_ENABLED]="true"
        
        local remote_type=$(prompt_choice "Remote backup type:" "S3" "SFTP" "Rsync")
        CONFIG_VALUES[REMOTE_BACKUP_TYPE]="$remote_type"
        
        case "$remote_type" in
            "S3")
                read -rp "S3 bucket name: " s3_bucket
                CONFIG_VALUES[S3_BUCKET]="$s3_bucket"
                read -rp "AWS region: " aws_region
                CONFIG_VALUES[AWS_REGION]="$aws_region"
                read -rp "AWS access key: " aws_key
                CONFIG_VALUES[AWS_ACCESS_KEY]="$aws_key"
                CONFIG_VALUES[AWS_SECRET_KEY]="$(prompt_password "AWS secret key")"
                ;;
            "SFTP")
                read -rp "SFTP host: " sftp_host
                CONFIG_VALUES[SFTP_HOST]="$sftp_host"
                read -rp "SFTP user: " sftp_user
                CONFIG_VALUES[SFTP_USER]="$sftp_user"
                read -rp "SFTP path: " sftp_path
                CONFIG_VALUES[SFTP_PATH]="$sftp_path"
                ;;
            "Rsync")
                read -rp "Rsync destination (user@host:/path): " rsync_dest
                CONFIG_VALUES[RSYNC_DEST]="$rsync_dest"
                ;;
        esac
    else
        CONFIG_VALUES[REMOTE_BACKUP_ENABLED]="false"
    fi
    
    log_success "Step 8 completed: Backup configured"
}

#==============================================================================
# STEP 9: LOGGING AND MONITORING
#==============================================================================

step_09_logging() {
    print_step_header 9 "Logging and Monitoring Configuration"
    
    cat << 'EOF'
Configure logging and monitoring settings.

EOF

    # Log level
    local log_level=$(prompt_choice "Log level:" "info" "debug" "warning" "error")
    CONFIG_VALUES[LOG_LEVEL]="$log_level"
    
    # Log retention
    local log_retention=$(prompt_with_default "Log retention (days)" "30")
    CONFIG_VALUES[LOG_RETENTION_DAYS]="$log_retention"
    
    # Structured logging
    if prompt_yes_no "Enable JSON structured logging?" "n"; then
        CONFIG_VALUES[JSON_LOGS]="true"
    else
        CONFIG_VALUES[JSON_LOGS]="false"
    fi
    
    # Monitoring configuration
    if [[ "${CONFIG_VALUES[INSTALL_PROMETHEUS]}" == "true" ]]; then
        log_info "Configuring Prometheus monitoring..."
        
        local scrape_interval=$(prompt_with_default "Metrics scrape interval (seconds)" "15")
        CONFIG_VALUES[PROMETHEUS_SCRAPE_INTERVAL]="${scrape_interval}s"
        
        local retention=$(prompt_with_default "Metrics retention (days)" "15")
        CONFIG_VALUES[PROMETHEUS_RETENTION]="${retention}d"
    fi
    
    # Alerting
    if [[ "${CONFIG_VALUES[INSTALL_PROMETHEUS]}" == "true" ]]; then
        if prompt_yes_no "Configure alerting?" "n"; then
            CONFIG_VALUES[ALERTING_ENABLED]="true"
            
            read -rp "Alert email address: " alert_email
            CONFIG_VALUES[ALERT_EMAIL]="$alert_email"
            
            # Alert thresholds
            local cpu_threshold=$(prompt_with_default "CPU alert threshold (%)" "80")
            CONFIG_VALUES[ALERT_CPU_THRESHOLD]="$cpu_threshold"
            
            local memory_threshold=$(prompt_with_default "Memory alert threshold (%)" "85")
            CONFIG_VALUES[ALERT_MEMORY_THRESHOLD]="$memory_threshold"
            
            local disk_threshold=$(prompt_with_default "Disk alert threshold (%)" "90")
            CONFIG_VALUES[ALERT_DISK_THRESHOLD]="$disk_threshold"
        else
            CONFIG_VALUES[ALERTING_ENABLED]="false"
        fi
    fi
    
    log_success "Step 9 completed: Logging and monitoring configured"
}

#==============================================================================
# STEP 10: RESOURCE LIMITS
#==============================================================================

step_10_resources() {
    print_step_header 10 "Resource Limits Configuration"
    
    cat << 'EOF'
Configure resource limits for containers.

This helps prevent any single service from consuming all system resources.

EOF

    # Get total system resources
    local total_memory=$(free -g | awk 'NR==2 {print $2}')
    local total_cpus=$(nproc)
    
    log_info "System resources: ${total_memory}GB RAM, ${total_cpus} CPUs"
    
    # Ollama resources (most important)
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        echo
        echo "Ollama Configuration:"
        
        local ollama_memory=$(prompt_with_default "Ollama memory limit (GB)" "8")
        CONFIG_VALUES[OLLAMA_MAX_MEMORY]="${ollama_memory}g"
        
        local ollama_cpus=$(prompt_with_default "Ollama CPU limit (cores)" "$((total_cpus / 2))")
        CONFIG_VALUES[OLLAMA_MAX_CPUS]="$ollama_cpus"
        
        # GPU support
        if prompt_yes_no "Enable GPU support for Ollama?" "n"; then
            CONFIG_VALUES[ENABLE_GPU]="true"
            
            # Detect GPU
            if command -v nvidia-smi &>/dev/null; then
                log_info "NVIDIA GPU detected"
                CONFIG_VALUES[GPU_TYPE]="nvidia"
            elif command -v rocm-smi &>/dev/null; then
                log_info "AMD GPU detected"
                CONFIG_VALUES[GPU_TYPE]="amd"
            else
                log_warning "No GPU detected, but GPU support enabled"
                CONFIG_VALUES[GPU_TYPE]="none"
            fi
        else
            CONFIG_VALUES[ENABLE_GPU]="false"
        fi
    fi
    
    # n8n resources
    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        echo
        echo "n8n Configuration:"
        local n8n_memory=$(prompt_with_default "n8n memory limit (GB)" "2")
        CONFIG_VALUES[N8N_MAX_MEMORY]="${n8n_memory}g"
    fi
    
    # PostgreSQL resources
    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
        echo
        echo "PostgreSQL Configuration:"
        local pg_memory=$(prompt_with_default "PostgreSQL memory limit (GB)" "${CONFIG_VALUES[POSTGRES_MAX_MEMORY]}")
        CONFIG_VALUES[POSTGRES_MAX_MEMORY]="${pg_memory}"
        
        # Connection limits
        local max_connections=$(prompt_with_default "Max connections" "100")
        CONFIG_VALUES[POSTGRES_MAX_CONNECTIONS]="$max_connections"
    fi
    
    # Redis resources
    if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
        echo
        echo "Redis Configuration:"
        local redis_memory=$(prompt_with_default "Redis memory limit (MB)" "512")
        CONFIG_VALUES[REDIS_MAX_MEMORY]="${redis_memory}mb"
        
        local eviction_policy=$(prompt_choice "Memory eviction policy:" "allkeys-lru" "volatile-lru" "noeviction")
        CONFIG_VALUES[REDIS_EVICTION_POLICY]="$eviction_policy"
    fi
    
    log_success "Step 10 completed: Resource limits configured"
}

#==============================================================================
# END OF PART 2/4
#==============================================================================
#!/bin/bash
################################################################################
# AI Platform Automation - System Setup Script
# Part 3/4: Wizard Steps 11-20 + Configuration Generation
################################################################################

#==============================================================================
# STEP 11: SSL/TLS CONFIGURATION
#==============================================================================

step_11_ssl() {
    print_step_header 11 "SSL/TLS Configuration"
    
    if [[ "${CONFIG_VALUES[BASE_DOMAIN]}" == "localhost" ]]; then
        log_info "Localhost deployment - SSL not required"
        CONFIG_VALUES[ENABLE_SSL]="false"
        return 0
    fi
    
    cat << 'EOF'
Configure SSL/TLS certificates.

Options:
  1) Let's Encrypt - Free automated certificates
  2) Self-signed - For testing/development
  3) Custom - Provide your own certificates
  4) None - HTTP only (not recommended for production)

EOF

    local ssl_option=$(prompt_choice "SSL configuration:" "Let's Encrypt" "Self-signed" "Custom" "None")
    
    case "$ssl_option" in
        "Let's Encrypt")
            CONFIG_VALUES[ENABLE_SSL]="true"
            CONFIG_VALUES[SSL_TYPE]="letsencrypt"
            
            # Email for Let's Encrypt
            local ssl_email
            while true; do
                read -rp "Email for SSL notifications: " ssl_email
                if is_valid_email "$ssl_email"; then
                    CONFIG_VALUES[SSL_EMAIL]="$ssl_email"
                    break
                else
                    log_error "Invalid email address"
                fi
            done
            
            # Staging for testing
            if [[ "${CONFIG_VALUES[ENVIRONMENT]}" != "production" ]]; then
                if prompt_yes_no "Use Let's Encrypt staging (for testing)?" "y"; then
                    CONFIG_VALUES[LETSENCRYPT_STAGING]="true"
                else
                    CONFIG_VALUES[LETSENCRYPT_STAGING]="false"
                fi
            else
                CONFIG_VALUES[LETSENCRYPT_STAGING]="false"
            fi
            
            log_info "Let's Encrypt will automatically obtain certificates"
            log_warning "Ensure DNS is configured and port 80/443 are accessible"
            ;;
            
        "Self-signed")
            CONFIG_VALUES[ENABLE_SSL]="true"
            CONFIG_VALUES[SSL_TYPE]="self-signed"
            
            log_warning "Self-signed certificates will generate browser warnings"
            log_info "Use this for development/testing only"
            
            # Certificate details
            read -rp "Organization name: " ssl_org
            CONFIG_VALUES[SSL_ORG]="$ssl_org"
            
            local ssl_country=$(prompt_with_default "Country code (2 letters)" "US")
            CONFIG_VALUES[SSL_COUNTRY]="$ssl_country"
            
            local ssl_validity=$(prompt_with_default "Certificate validity (days)" "365")
            CONFIG_VALUES[SSL_VALIDITY_DAYS]="$ssl_validity"
            ;;
            
        "Custom")
            CONFIG_VALUES[ENABLE_SSL]="true"
            CONFIG_VALUES[SSL_TYPE]="custom"
            
            log_info "You will need to provide certificate files later"
            
            read -rp "Path to certificate file (.crt): " ssl_cert
            CONFIG_VALUES[SSL_CERT_PATH]="$ssl_cert"
            
            read -rp "Path to private key file (.key): " ssl_key
            CONFIG_VALUES[SSL_KEY_PATH]="$ssl_key"
            
            read -rp "Path to CA bundle (optional): " ssl_ca
            CONFIG_VALUES[SSL_CA_PATH]="$ssl_ca"
            
            # Validate files exist
            for file in "$ssl_cert" "$ssl_key"; do
                if [[ ! -f "$file" ]]; then
                    log_error "File not found: $file"
                    return 1
                fi
            done
            ;;
            
        "None")
            CONFIG_VALUES[ENABLE_SSL]="false"
            log_warning "SSL disabled - connections will not be encrypted"
            
            if [[ "${CONFIG_VALUES[ENVIRONMENT]}" == "production" ]]; then
                log_error "SSL is strongly recommended for production"
                if ! prompt_yes_no "Continue without SSL?" "n"; then
                    return 1
                fi
            fi
            ;;
    esac
    
    # HSTS configuration
    if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]]; then
        if prompt_yes_no "Enable HSTS (HTTP Strict Transport Security)?" "y"; then
            CONFIG_VALUES[ENABLE_HSTS]="true"
            local hsts_age=$(prompt_with_default "HSTS max-age (seconds)" "31536000")
            CONFIG_VALUES[HSTS_MAX_AGE]="$hsts_age"
        else
            CONFIG_VALUES[ENABLE_HSTS]="false"
        fi
    fi
    
    log_success "Step 11 completed: SSL configured"
}

#==============================================================================
# STEP 12: AUTHENTICATION AND SECURITY
#==============================================================================

step_12_security() {
    print_step_header 12 "Authentication and Security"
    
    cat << 'EOF'
Configure authentication and security settings.

EOF

    # Admin credentials
    echo "Admin User Configuration:"
    
    local admin_user=$(prompt_with_default "Admin username" "admin")
    CONFIG_VALUES[ADMIN_USERNAME]="$admin_user"
    
    if prompt_yes_no "Generate random admin password?" "y"; then
        CONFIG_VALUES[ADMIN_PASSWORD]="$(generate_random_password 24)"
        log_info "Random password generated (will be shown at end of setup)"
    else
        CONFIG_VALUES[ADMIN_PASSWORD]="$(prompt_password "Enter admin password")"
    fi
    
    # API key generation
    echo
    echo "API Key Configuration:"
    
    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        CONFIG_VALUES[N8N_ENCRYPTION_KEY]="$(generate_random_password 32)"
        log_info "n8n encryption key generated"
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}" == "true" ]]; then
        CONFIG_VALUES[WEBUI_JWT_SECRET]="$(generate_random_password 64)"
        log_info "Open WebUI JWT secret generated"
    fi
    
    # Security features
    echo
    echo "Security Features:"
    
    if prompt_yes_no "Enable rate limiting?" "y"; then
        CONFIG_VALUES[RATE_LIMIT_ENABLED]="true"
        
        local rate_limit=$(prompt_with_default "Requests per minute (per IP)" "60")
        CONFIG_VALUES[RATE_LIMIT_RPM]="$rate_limit"
    else
        CONFIG_VALUES[RATE_LIMIT_ENABLED]="false"
    fi
    
    if prompt_yes_no "Enable IP whitelist?" "n"; then
        CONFIG_VALUES[IP_WHITELIST_ENABLED]="true"
        
        echo "Enter allowed IP addresses (one per line, empty line to finish):"
        local ips=()
        while true; do
            read -rp "IP address: " ip
            [[ -z "$ip" ]] && break
            if is_valid_ip "$ip"; then
                ips+=("$ip")
            else
                log_warning "Invalid IP address: $ip"
            fi
        done
        CONFIG_VALUES[ALLOWED_IPS]="${ips[*]}"
    else
        CONFIG_VALUES[IP_WHITELIST_ENABLED]="false"
    fi
    
    # Fail2ban
    if prompt_yes_no "Enable fail2ban integration?" "n"; then
        CONFIG_VALUES[FAIL2BAN_ENABLED]="true"
        
        local max_retry=$(prompt_with_default "Max login attempts" "5")
        CONFIG_VALUES[FAIL2BAN_MAX_RETRY]="$max_retry"
        
        local ban_time=$(prompt_with_default "Ban time (seconds)" "3600")
        CONFIG_VALUES[FAIL2BAN_BAN_TIME]="$ban_time"
    else
        CONFIG_VALUES[FAIL2BAN_ENABLED]="false"
    fi
    
    # Session configuration
    echo
    echo "Session Configuration:"
    
    local session_timeout=$(prompt_with_default "Session timeout (minutes)" "60")
    CONFIG_VALUES[SESSION_TIMEOUT]="$session_timeout"
    
    if prompt_yes_no "Enable remember me functionality?" "y"; then
        CONFIG_VALUES[REMEMBER_ME_ENABLED]="true"
        local remember_duration=$(prompt_with_default "Remember me duration (days)" "30")
        CONFIG_VALUES[REMEMBER_ME_DURATION]="$remember_duration"
    else
        CONFIG_VALUES[REMEMBER_ME_ENABLED]="false"
    fi
    
    log_success "Step 12 completed: Security configured"
}

#==============================================================================
# STEP 13: MODEL CONFIGURATION
#==============================================================================

step_13_models() {
    print_step_header 13 "AI Model Configuration"
    
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" != "true" ]]; then
        log_info "Ollama not installed, skipping model configuration"
        return 0
    fi
    
    cat << 'EOF'
Configure which AI models to download.

Available models:
  • llama3.2:3b    - Fast, efficient, good for most tasks (2GB)
  • llama3.2:1b    - Ultra-fast, minimal resources (1GB)
  • qwen2.5:7b     - Excellent reasoning and coding (4GB)
  • mistral:7b     - Balanced performance (4GB)
  • codellama:7b   - Specialized for code (4GB)
  • phi3:mini      - Microsoft's efficient model (2GB)

Custom models can be added later via Ollama CLI.

EOF

    # Default models
    local -a selected_models=()
    
    if prompt_yes_no "Install llama3.2:3b (recommended)?" "y"; then
        selected_models+=("llama3.2:3b")
    fi
    
    if prompt_yes_no "Install qwen2.5:7b (good for coding)?" "n"; then
        selected_models+=("qwen2.5:7b")
    fi
    
    if prompt_yes_no "Install mistral:7b?" "n"; then
        selected_models+=("mistral:7b")
    fi
    
    if prompt_yes_no "Install codellama:7b (specialized for code)?" "n"; then
        selected_models+=("codellama:7b")
    fi
    
    if prompt_yes_no "Install phi3:mini (lightweight)?" "n"; then
        selected_models+=("phi3:mini")
    fi
    
    # Custom models
    if prompt_yes_no "Add custom models?" "n"; then
        echo "Enter model names (format: name:tag), empty line to finish:"
        while true; do
            read -rp "Model: " custom_model
            [[ -z "$custom_model" ]] && break
            selected_models+=("$custom_model")
        done
    fi
    
    if ((${#selected_models[@]} == 0)); then
        log_warning "No models selected - you can download them later"
    else
        CONFIG_VALUES[OLLAMA_MODELS]="${selected_models[*]}"
        log_info "Selected models: ${selected_models[*]}"
        
        # Estimate storage
        local estimated_size=0
        for model in "${selected_models[@]}"; do
            case "$model" in
                *:1b) ((estimated_size += 1)) ;;
                *:3b) ((estimated_size += 2)) ;;
                *:7b) ((estimated_size += 4)) ;;
                *:13b) ((estimated_size += 8)) ;;
                *:34b) ((estimated_size += 20)) ;;
                *:70b) ((estimated_size += 40)) ;;
                *) ((estimated_size += 5)) ;;
            esac
        done
        
        log_info "Estimated storage required: ${estimated_size}GB"
    fi
    
    # Model download timing
    if ((${#selected_models[@]} > 0)); then
        local download_timing=$(prompt_choice "When to download models:" "During setup" "After setup" "Manual")
        CONFIG_VALUES[MODEL_DOWNLOAD_TIMING]="$download_timing"
    fi
    
    # Default model
    if ((${#selected_models[@]} > 0)); then
        echo
        echo "Select default model:"
        select default_model in "${selected_models[@]}"; do
            if [[ -n "$default_model" ]]; then
                CONFIG_VALUES[DEFAULT_MODEL]="$default_model"
                log_info "Default model: $default_model"
                break
            fi
        done
    fi
    
    log_success "Step 13 completed: Models configured"
}

#==============================================================================
# STEP 14: NETWORK CONFIGURATION
#==============================================================================

step_14_network() {
    print_step_header 14 "Network Configuration"
    
    cat << 'EOF'
Configure Docker networking settings.

EOF

    # Docker network name
    local network_name=$(prompt_with_default "Docker network name" "aiplatform-network")
    CONFIG_VALUES[DOCKER_NETWORK_NAME]="$network_name"
    
    # Network driver
    local network_driver=$(prompt_choice "Network driver:" "bridge" "overlay" "host")
    CONFIG_VALUES[DOCKER_NETWORK_DRIVER]="$network_driver"
    
    if [[ "$network_driver" == "overlay" ]]; then
        log_info "Overlay network selected - Docker Swarm required"
        CONFIG_VALUES[DOCKER_SWARM_MODE]="true"
    fi
    
    # Subnet configuration
    if prompt_yes_no "Configure custom subnet?" "n"; then
        read -rp "Subnet (CIDR notation, e.g., 172.28.0.0/16): " subnet
        CONFIG_VALUES[DOCKER_SUBNET]="$subnet"
        
        read -rp "Gateway (e.g., 172.28.0.1): " gateway
        CONFIG_VALUES[DOCKER_GATEWAY]="$gateway"
    else
        CONFIG_VALUES[DOCKER_SUBNET]="172.28.0.0/16"
        CONFIG_VALUES[DOCKER_GATEWAY]="172.28.0.1"
    fi
    
    # DNS configuration
    if prompt_yes_no "Configure custom DNS servers?" "n"; then
        echo "Enter DNS servers (one per line, empty to finish):"
        local dns_servers=()
        while true; do
            read -rp "DNS server: " dns
            [[ -z "$dns" ]] && break
            if is_valid_ip "$dns"; then
                dns_servers+=("$dns")
            else
                log_warning "Invalid IP address: $dns"
            fi
        done
        CONFIG_VALUES[DOCKER_DNS]="${dns_servers[*]}"
    fi
    
    # MTU configuration
    if prompt_yes_no "Configure custom MTU?" "n"; then
        local mtu=$(prompt_with_default "MTU value" "1500")
        CONFIG_VALUES[DOCKER_MTU]="$mtu"
    fi
    
    log_success "Step 14 completed: Network configured"
}

#==============================================================================
# STEP 15: PERFORMANCE TUNING
#==============================================================================

step_15_performance() {
    print_step_header 15 "Performance Tuning"
    
    cat << 'EOF'
Configure performance optimization settings.

EOF

    # Performance profile
    local perf_profile=$(prompt_choice "Performance profile:" "Balanced" "Performance" "Resource-saving")
    
    case "$perf_profile" in
        "Balanced")
            CONFIG_VALUES[PERF_PROFILE]="balanced"
            CONFIG_VALUES[WORKER_PROCESSES]="auto"
            CONFIG_VALUES[MAX_CONNECTIONS]="1024"
            ;;
        "Performance")
            CONFIG_VALUES[PERF_PROFILE]="performance"
            CONFIG_VALUES[WORKER_PROCESSES]="$(nproc)"
            CONFIG_VALUES[MAX_CONNECTIONS]="4096"
            ;;
        "Resource-saving")
            CONFIG_VALUES[PERF_PROFILE]="resource-saving"
            CONFIG_VALUES[WORKER_PROCESSES]="2"
            CONFIG_VALUES[MAX_CONNECTIONS]="512"
            ;;
    esac
    
    log_info "Performance profile: ${CONFIG_VALUES[PERF_PROFILE]}"
    
    # Nginx tuning
    if [[ "${CONFIG_VALUES[INSTALL_NGINX]}" == "true" ]]; then
        echo
        echo "Nginx Performance:"
        
        if prompt_yes_no "Enable Nginx caching?" "y"; then
            CONFIG_VALUES[NGINX_CACHE_ENABLED]="true"
            
            local cache_size=$(prompt_with_default "Cache size (MB)" "500")
            CONFIG_VALUES[NGINX_CACHE_SIZE]="${cache_size}m"
            
            local cache_time=$(prompt_with_default "Cache time (minutes)" "60")
            CONFIG_VALUES[NGINX_CACHE_TIME]="${cache_time}m"
        else
            CONFIG_VALUES[NGINX_CACHE_ENABLED]="false"
        fi
        
        if prompt_yes_no "Enable Nginx compression?" "y"; then
            CONFIG_VALUES[NGINX_GZIP_ENABLED]="true"
            local gzip_level=$(prompt_with_default "Gzip compression level (1-9)" "6")
            CONFIG_VALUES[NGINX_GZIP_LEVEL]="$gzip_level"
        else
            CONFIG_VALUES[NGINX_GZIP_ENABLED]="false"
        fi
    fi
    
    # Database tuning
    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
        echo
        echo "PostgreSQL Performance:"
        
        if prompt_yes_no "Enable PostgreSQL performance tuning?" "y"; then
            CONFIG_VALUES[POSTGRES_TUNING_ENABLED]="true"
            
            # Calculate based on available memory
            local total_mem=$(free -m | awk 'NR==2 {print $2}')
            local shared_buffers=$((total_mem / 4))
            local effective_cache=$((total_mem / 2))
            
            log_info "Recommended PostgreSQL settings (based on ${total_mem}MB RAM):"
            log_info "  shared_buffers: ${shared_buffers}MB"
            log_info "  effective_cache_size: ${effective_cache}MB"
            
            if prompt_yes_no "Use recommended settings?" "y"; then
                CONFIG_VALUES[POSTGRES_SHARED_BUFFERS]="${shared_buffers}MB"
                CONFIG_VALUES[POSTGRES_EFFECTIVE_CACHE]="${effective_cache}MB"
            else
                local custom_shared=$(prompt_with_default "shared_buffers (MB)" "$shared_buffers")
                CONFIG_VALUES[POSTGRES_SHARED_BUFFERS]="${custom_shared}MB"
                
                local custom_cache=$(prompt_with_default "effective_cache_size (MB)" "$effective_cache")
                CONFIG_VALUES[POSTGRES_EFFECTIVE_CACHE]="${custom_cache}MB"
            fi
        else
            CONFIG_VALUES[POSTGRES_TUNING_ENABLED]="false"
        fi
    fi
    
    # Redis tuning
    if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
        echo
        echo "Redis Performance:"
        
        if prompt_yes_no "Enable Redis persistence?" "y"; then
            CONFIG_VALUES[REDIS_PERSISTENCE_ENABLED]="true"
            
            local persistence_type=$(prompt_choice "Persistence type:" "RDB (snapshots)" "AOF (append-only)" "Both")
            case "$persistence_type" in
                "RDB (snapshots)")
                    CONFIG_VALUES[REDIS_PERSISTENCE]="rdb"
                    ;;
                "AOF (append-only)")
                    CONFIG_VALUES[REDIS_PERSISTENCE]="aof"
                    ;;
                "Both")
                    CONFIG_VALUES[REDIS_PERSISTENCE]="both"
                    ;;
            esac
        else
            CONFIG_VALUES[REDIS_PERSISTENCE_ENABLED]="false"
        fi
    fi
    
    log_success "Step 15 completed: Performance tuning configured"
}

#==============================================================================
# STEP 16: MAINTENANCE AND UPDATES
#==============================================================================

step_16_maintenance() {
    print_step_header 16 "Maintenance and Updates"
    
    cat << 'EOF'
Configure maintenance and update settings.

EOF

    # Automatic updates
    if prompt_yes_no "Enable automatic container updates?" "n"; then
        CONFIG_VALUES[AUTO_UPDATE_ENABLED]="true"
        
        if [[ "${CONFIG_VALUES[INSTALL_WATCHTOWER]}" != "true" ]]; then
            log_info "Watchtower will be enabled for automatic updates"
            CONFIG_VALUES[INSTALL_WATCHTOWER]="true"
        fi
        
        local update_schedule=$(prompt_choice "Update schedule:" "Daily at 3 AM" "Weekly on Sunday" "Custom")
        case "$update_schedule" in
            "Daily at 3 AM")
                CONFIG_VALUES[UPDATE_SCHEDULE]="0 0 3 * * *"
                ;;
            "Weekly on Sunday")
                CONFIG_VALUES[UPDATE_SCHEDULE]="0 0 3 * * 0"
                ;;
            "Custom")
                read -rp "Enter cron expression: " custom_schedule
                CONFIG_VALUES[UPDATE_SCHEDULE]="$custom_schedule"
                ;;
        esac
    else
        CONFIG_VALUES[AUTO_UPDATE_ENABLED]="false"
    fi
    
    # Health checks
    if prompt_yes_no "Enable health check monitoring?" "y"; then
        CONFIG_VALUES[HEALTH_CHECK_ENABLED]="true"
        
        local check_interval=$(prompt_with_default "Health check interval (seconds)" "30")
        CONFIG_VALUES[HEALTH_CHECK_INTERVAL]="${check_interval}s"
        
        local check_timeout=$(prompt_with_default "Health check timeout (seconds)" "10")
        CONFIG_VALUES[HEALTH_CHECK_TIMEOUT]="${check_timeout}s"
        
        local check_retries=$(prompt_with_default "Health check retries" "3")
        CONFIG_VALUES[HEALTH_CHECK_RETRIES]="$check_retries"
    else
        CONFIG_VALUES[HEALTH_CHECK_ENABLED]="false"
    fi
    
    # Cleanup policies
    if prompt_yes_no "Enable automatic cleanup of old data?" "y"; then
        CONFIG_VALUES[AUTO_CLEANUP_ENABLED]="true"
        
        local cleanup_schedule=$(prompt_with_default "Cleanup schedule (cron)" "0 0 2 * * *")
        CONFIG_VALUES[CLEANUP_SCHEDULE]="$cleanup_schedule"
        
        # Log cleanup
        local log_retention=$(prompt_with_default "Keep logs for (days)" "${CONFIG_VALUES[LOG_RETENTION_DAYS]}")
        CONFIG_VALUES[LOG_RETENTION_DAYS]="$log_retention"
        
        # Docker cleanup
        if prompt_yes_no "Cleanup unused Docker images/volumes?" "y"; then
            CONFIG_VALUES[DOCKER_CLEANUP_ENABLED]="true"
        else
            CONFIG_VALUES[DOCKER_CLEANUP_ENABLED]="false"
        fi
    else
        CONFIG_VALUES[AUTO_CLEANUP_ENABLED]="false"
    fi
    
    log_success "Step 16 completed: Maintenance configured"
}

#==============================================================================
# STEP 17: NOTIFICATION CONFIGURATION
#==============================================================================

step_17_notifications() {
    print_step_header 17 "Notification Configuration"
    
    cat << 'EOF'
Configure notifications for system events.

EOF

    if prompt_yes_no "Enable notifications?" "n"; then
        CONFIG_VALUES[NOTIFICATIONS_ENABLED]="true"
        
        # Notification methods
        echo "Select notification methods (multiple allowed):"
        
        if prompt_yes_no "  Email notifications?" "y"; then
            CONFIG_VALUES[NOTIFY_EMAIL]="true"
            
            read -rp "SMTP server: " smtp_server
            CONFIG_VALUES[SMTP_SERVER]="$smtp_server"
            
            read -rp "SMTP port: " smtp_port
            CONFIG_VALUES[SMTP_PORT]="$smtp_port"
            
            read -rp "SMTP username: " smtp_user
            CONFIG_VALUES[SMTP_USER]="$smtp_user"
            
            CONFIG_VALUES[SMTP_PASSWORD]="$(prompt_password "SMTP password")"
            
            read -rp "Notification email (recipient): " notify_email
            CONFIG_VALUES[NOTIFICATION_EMAIL]="$notify_email"
            
            read -rp "From email address: " from_email
            CONFIG_VALUES[SMTP_FROM]="$from_email"
        else
            CONFIG_VALUES[NOTIFY_EMAIL]="false"
        fi
        
        if prompt_yes_no "  Slack notifications?" "n"; then
            CONFIG_VALUES[NOTIFY_SLACK]="true"
            read -rp "Slack webhook URL: " slack_webhook
            CONFIG_VALUES[SLACK_WEBHOOK]="$slack_webhook"
        else
            CONFIG_VALUES[NOTIFY_SLACK]="false"
        fi
        
        if prompt_yes_no "  Discord notifications?" "n"; then
            CONFIG_VALUES[NOTIFY_DISCORD]="true"
            read -rp "Discord webhook URL: " discord_webhook
            CONFIG_VALUES[DISCORD_WEBHOOK]="$discord_webhook"
        else
            CONFIG_VALUES[NOTIFY_DISCORD]="false"
        fi
        
        if prompt_yes_no "  Telegram notifications?" "n"; then
            CONFIG_VALUES[NOTIFY_TELEGRAM]="true"
            read -rp "Telegram bot token: " telegram_token
            CONFIG_VALUES[TELEGRAM_TOKEN]="$telegram_token"
            read -rp "Telegram chat ID: " telegram_chat
            CONFIG_VALUES[TELEGRAM_CHAT_ID]="$telegram_chat"
        else
            CONFIG_VALUES[NOTIFY_TELEGRAM]="false"
        fi
        
        # Notification events
        echo
        echo "Select events to notify about:"
        
        if prompt_yes_no "  Service failures?" "y"; then
            CONFIG_VALUES[NOTIFY_ON_FAILURE]="true"
        else
            CONFIG_VALUES[NOTIFY_ON_FAILURE]="false"
        fi
        
        if prompt_yes_no "  Successful backups?" "n"; then
            CONFIG_VALUES[NOTIFY_ON_BACKUP]="true"
        else
            CONFIG_VALUES[NOTIFY_ON_BACKUP]="false"
        fi
        
        if prompt_yes_no "  System updates?" "y"; then
            CONFIG_VALUES[NOTIFY_ON_UPDATE]="true"
        else
            CONFIG_VALUES[NOTIFY_ON_UPDATE]="false"
        fi
        
        if prompt_yes_no "  Resource alerts?" "y"; then
            CONFIG_VALUES[NOTIFY_ON_RESOURCE_ALERT]="true"
        else
            CONFIG_VALUES[NOTIFY_ON_RESOURCE_ALERT]="false"
        fi
    else
        CONFIG_VALUES[NOTIFICATIONS_ENABLED]="false"
    fi
    
    log_success "Step 17 completed: Notifications configured"
}

#==============================================================================
# STEP 18: INTEGRATION CONFIGURATION
#==============================================================================

step_18_integrations() {
    print_step_header 18 "External Integrations"
    
    cat << 'EOF'
Configure external service integrations.

EOF

    # OpenAI API (for hybrid approach)
    if prompt_yes_no "Configure OpenAI API integration?" "n"; then
        CONFIG_VALUES[OPENAI_ENABLED]="true"
        
        read -rp "OpenAI API key: " openai_key
        CONFIG_VALUES[OPENAI_API_KEY]="$openai_key"
        
        local openai_model=$(prompt_with_default "Default OpenAI model" "gpt-4")
        CONFIG_VALUES[OPENAI_DEFAULT_MODEL]="$openai_model"
    else
        CONFIG_VALUES[OPENAI_ENABLED]="false"
    fi
    
    # Anthropic Claude
    if prompt_yes_no "Configure Anthropic Claude integration?" "n"; then
        CONFIG_VALUES[ANTHROPIC_ENABLED]="true"
        read -rp "Anthropic API key: " anthropic_key
        CONFIG_VALUES[ANTHROPIC_API_KEY]="$anthropic_key"
    else
        CONFIG_VALUES[ANTHROPIC_ENABLED]="false"
    fi
    
    # AWS integration (for S3, etc.)
    if prompt_yes_no "Configure AWS integration?" "n"; then
        CONFIG_VALUES[AWS_ENABLED]="true"
        read -rp "AWS access key ID: " aws_key
        CONFIG_VALUES[AWS_ACCESS_KEY_ID]="$aws_key"
        CONFIG_VALUES[AWS_SECRET_ACCESS_KEY]="$(prompt_password "AWS secret access key")"
        read -rp "AWS region: " aws_region
        CONFIG_VALUES[AWS_REGION]="$aws_region"
    else
        CONFIG_VALUES[AWS_ENABLED]="false"
    fi
    
    # Git integration (for backups/sync)
    if prompt_yes_no "Configure Git integration?" "n"; then
        CONFIG_VALUES[GIT_ENABLED]="true"
        read -rp "Git repository URL: " git_repo
        CONFIG_VALUES[GIT_REPO]="$git_repo"
        read -rp "Git branch: " git_branch
        CONFIG_VALUES[GIT_BRANCH]="$git_branch"
        
        if prompt_yes_no "Use SSH key for authentication?" "y"; then
            read -rp "Path to SSH private key: " ssh_key
            CONFIG_VALUES[GIT_SSH_KEY]="$ssh_key"
        else
            read -rp "Git username: " git_user
            CONFIG_VALUES[GIT_USERNAME]="$git_user"
            CONFIG_VALUES[GIT_PASSWORD]="$(prompt_password "Git password/token")"
        fi
    else
        CONFIG_VALUES[GIT_ENABLED]="false"
    fi
    
    log_success "Step 18 completed: Integrations configured"
}

#==============================================================================
# STEP 19: REVIEW CONFIGURATION
#==============================================================================

step_19_review() {
    print_step_header 19 "Configuration Review"
    
    cat << 'EOF'
Please review your configuration before proceeding.

EOF

    print_section_break
    echo "ENVIRONMENT:"
    echo "  Environment: ${CONFIG_VALUES[ENVIRONMENT]}"
    echo "  Project Name: ${CONFIG_VALUES[COMPOSE_PROJECT_NAME]}"
    echo "  Base Domain: ${CONFIG_VALUES[BASE_DOMAIN]}"
    echo "  Data Root: ${CONFIG_VALUES[DATA_ROOT]}"
    
    print_section_break
    echo "SERVICES:"
    echo "  Ollama: ${CONFIG_VALUES[INSTALL_OLLAMA]}"
    echo "  Open WebUI: ${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}"
    echo "  n8n: ${CONFIG_VALUES[INSTALL_N8N]}"
    echo "  PostgreSQL: ${CONFIG_VALUES[INSTALL_POSTGRES]}"
    echo "  Redis: ${CONFIG_VALUES[INSTALL_REDIS]}"
    echo "  Nginx: ${CONFIG_VALUES[INSTALL_NGINX]}"
    echo "  Prometheus: ${CONFIG_VALUES[INSTALL_PROMETHEUS]}"
    echo "  Grafana: ${CONFIG_VALUES[INSTALL_GRAFANA]}"
    echo "  Portainer: ${CONFIG_VALUES[INSTALL_PORTAINER]}"
    
    print_section_break
    echo "PORTS:"
    [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]] && echo "  Ollama: ${CONFIG_VALUES[OLLAMA_PORT]}"
    [[ "${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}" == "true" ]] && echo "  Open WebUI: ${CONFIG_VALUES[OPEN_WEBUI_PORT]}"
    [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]] && echo "  n8n: ${CONFIG_VALUES[N8N_PORT]}"
    [[ "${CONFIG_VALUES[INSTALL_NGINX]}" == "true" ]] && echo "  Nginx HTTP: ${CONFIG_VALUES[NGINX_HTTP_PORT]}"
    [[ "${CONFIG_VALUES[INSTALL_NGINX]}" == "true" ]] && echo "  Nginx HTTPS: ${CONFIG_VALUES[NGINX_HTTPS_PORT]}"
    
    print_section_break
    echo "SECURITY:"
    echo "  SSL Enabled: ${CONFIG_VALUES[ENABLE_SSL]}"
    [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]] && echo "  SSL Type: ${CONFIG_VALUES[SSL_TYPE]}"
    echo "  Rate Limiting: ${CONFIG_VALUES[RATE_LIMIT_ENABLED]}"
    echo "  IP Whitelist: ${CONFIG_VALUES[IP_WHITELIST_ENABLED]}"
    
    print_section_break
    echo "FEATURES:"
    echo "  Backups: ${CONFIG_VALUES[BACKUP_ENABLED]}"
    echo "  Monitoring: ${CONFIG_VALUES[INSTALL_PROMETHEUS]}"
    echo "  Notifications: ${CONFIG_VALUES[NOTIFICATIONS_ENABLED]}"
    echo "  Auto Updates: ${CONFIG_VALUES[AUTO_UPDATE_ENABLED]}"
    
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]] && [[ -n "${CONFIG_VALUES[OLLAMA_MODELS]:-}" ]]; then
        print_section_break
        echo "AI MODELS:"
        echo "  ${CONFIG_VALUES[OLLAMA_MODELS]}"
        echo "  Default: ${CONFIG_VALUES[DEFAULT_MODEL]:-None}"
    fi
    
    print_section_break
    
    if ! prompt_yes_no "Configuration looks good?" "y"; then
        log_warning "Configuration review failed"
        
        if prompt_yes_no "Start wizard over?" "y"; then
            log_info "Restarting wizard..."
            return 2  # Special return code to restart
        else
            log_error "Setup cancelled by user"
            exit 0
        fi
    fi
    
    log_success "Step 19 completed: Configuration reviewed and approved"
}

#==============================================================================
# STEP 20: GENERATE CONFIGURATION FILES
#==============================================================================

step_20_generate_configs() {
    print_step_header 20 "Generate Configuration Files"
    
    log_step "Generating configuration files..."
    
    # Create directories
    log_info "Creating directory structure..."
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "${CONFIG_VALUES[DATA_ROOT]}"
    mkdir -p "${CONFIG_DIR}/nginx/conf.d"
    mkdir -p "${CONFIG_DIR}/nginx/ssl"
    mkdir -p "${CONFIG_DIR}/postgres"
    mkdir -p "${CONFIG_VALUES[DATA_ROOT]}/postgres"
    mkdir -p "${CONFIG_VALUES[DATA_ROOT]}/redis"
    
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        mkdir -p "${CONFIG_VALUES[OLLAMA_MODELS_DIR]}"
    fi
    
    # Generate .env file
    log_info "Generating .env file..."
    if ! generate_env_file; then
        log_error "Failed to generate .env file"
        return 1
    fi
    
    # Generate docker-compose.yml
    log_info "Generating docker-compose.yml..."
    if ! generate_docker_compose; then
        log_error "Failed to generate docker-compose.yml"
        return 1
    fi
    
    # Generate Nginx config
    if [[ "${CONFIG_VALUES[INSTALL_NGINX]}" == "true" ]]; then
        log_info "Generating Nginx configuration..."
        if ! generate_nginx_config; then
            log_error "Failed to generate Nginx configuration"
            return 1
        fi
    fi
    
    # Generate backup scripts
    if [[ "${CONFIG_VALUES[BACKUP_ENABLED]}" == "true" ]]; then
        log_info "Generating backup scripts..."
        if ! generate_backup_scripts; then
            log_error "Failed to generate backup scripts"
            return 1
        fi
    fi
    
    # Set permissions
    log_info "Setting permissions..."
    chmod 600 "$ENV_FILE"
    chmod 644 "$DOCKER_COMPOSE_FILE"
    
    if [[ -f "${SCRIPT_DIR}/backup.sh" ]]; then
        chmod +x "${SCRIPT_DIR}/backup.sh"
    fi
    
    if [[ -f "${SCRIPT_DIR}/restore.sh" ]]; then
        chmod +x "${SCRIPT_DIR}/restore.sh"
    fi
    
    log_success "Step 20 completed: Configuration files generated"
    
    # Save configuration summary
    save_config_summary
}

#==============================================================================
# CONFIGURATION GENERATION FUNCTIONS
#==============================================================================

generate_env_file() {
    local env_content=""
    
    # Header
    env_content+="# AI Platform Configuration\n"
    env_content+="# Generated: $(date)\n"
    env_content+="# DO NOT COMMIT THIS FILE TO VERSION CONTROL\n\n"
    
    # Environment
    env_content+="# Environment Settings\n"
    env_content+="ENVIRONMENT=${CONFIG_VALUES[ENVIRONMENT]}\n"
    env_content+="COMPOSE_PROJECT_NAME=${CONFIG_VALUES[COMPOSE_PROJECT_NAME]}\n"
    env_content+="BASE_DOMAIN=${CONFIG_VALUES[BASE_DOMAIN]}\n"
    env_content+="DATA_ROOT=${CONFIG_VALUES[DATA_ROOT]}\n"
    env_content+="DEBUG=${CONFIG_VALUES[DEBUG]:-false}\n"
    env_content+="LOG_LEVEL=${CONFIG_VALUES[LOG_LEVEL]:-info}\n\n"
    
    # Ports
    env_content+="# Service Ports\n"
    env_content+="OLLAMA_PORT=${CONFIG_VALUES[OLLAMA_PORT]}\n"
    env_content+="OPEN_WEBUI_PORT=${CONFIG_VALUES[OPEN_WEBUI_PORT]}\n"
    env_content+="N8N_PORT=${CONFIG_VALUES[N8N_PORT]}\n"
    env_content+="NGINX_HTTP_PORT=${CONFIG_VALUES[NGINX_HTTP_PORT]}\n"
    env_content+="NGINX_HTTPS_PORT=${CONFIG_VALUES[NGINX_HTTPS_PORT]}\n"
    env_content+="POSTGRES_PORT=${CONFIG_VALUES[POSTGRES_PORT]}\n"
    env_content+="REDIS_PORT=${CONFIG_VALUES[REDIS_PORT]}\n\n"
    
    # Database
    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
        env_content+="# PostgreSQL Configuration\n"
        env_content+="POSTGRES_USER=${CONFIG_VALUES[POSTGRES_USER]}\n"
        env_content+="POSTGRES_PASSWORD=${CONFIG_VALUES[POSTGRES_PASSWORD]}\n"
        env_content+="POSTGRES_DB=${CONFIG_VALUES[POSTGRES_DB]}\n"
        env_content+="POSTGRES_MAX_CONNECTIONS=${CONFIG_VALUES[POSTGRES_MAX_CONNECTIONS]:-100}\n"
        env_content+="POSTGRES_SHARED_BUFFERS=${CONFIG_VALUES[POSTGRES_SHARED_BUFFERS]:-256MB}\n"
        env_content+="POSTGRES_EFFECTIVE_CACHE=${CONFIG_VALUES[POSTGRES_EFFECTIVE_CACHE]:-1GB}\n\n"
    fi
    
    # Redis
    if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
        env_content+="# Redis Configuration\n"
        env_content+="REDIS_MAX_MEMORY=${CONFIG_VALUES[REDIS_MAX_MEMORY]:-512mb}\n"
        env_content+="REDIS_EVICTION_POLICY=${CONFIG_VALUES[REDIS_EVICTION_POLICY]:-allkeys-lru}\n\n"
    fi
    
    # Security
    env_content+="# Security\n"
    env_content+="ADMIN_USERNAME=${CONFIG_VALUES[ADMIN_USERNAME]}\n"
    env_content+="ADMIN_PASSWORD=${CONFIG_VALUES[ADMIN_PASSWORD]}\n"
    
    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        env_content+="N8N_ENCRYPTION_KEY=${CONFIG_VALUES[N8N_ENCRYPTION_KEY]}\n"
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}" == "true" ]]; then
        env_content+="WEBUI_JWT_SECRET=${CONFIG_VALUES[WEBUI_JWT_SECRET]}\n"
    fi
    
    env_content+="\n"
    
    # SSL
    if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]]; then
        env_content+="# SSL Configuration\n"
        env_content+="ENABLE_SSL=true\n"
        env_content+="SSL_TYPE=${CONFIG_VALUES[SSL_TYPE]}\n"
        
        if [[ "${CONFIG_VALUES[SSL_TYPE]}" == "letsencrypt" ]]; then
            env_content+="SSL_EMAIL=${CONFIG_VALUES[SSL_EMAIL]}\n"
            env_content+="LETSENCRYPT_STAGING=${CONFIG_VALUES[LETSENCRYPT_STAGING]:-false}\n"
        fi
        
        env_content+="\n"
    fi
    
    # Ollama
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        env_content+="# Ollama Configuration\n"
        env_content+="OLLAMA_MODELS_DIR=${CONFIG_VALUES[OLLAMA_MODELS_DIR]}\n"
        env_content+="OLLAMA_MAX_MEMORY=${CONFIG_VALUES[OLLAMA_MAX_MEMORY]:-8g}\n"
        env_content+="OLLAMA_MAX_CPUS=${CONFIG_VALUES[OLLAMA_MAX_CPUS]:-4}\n"
        env_content+="ENABLE_GPU=${CONFIG_VALUES[ENABLE_GPU]:-false}\n"
        
        if [[ -n "${CONFIG_VALUES[OLLAMA_MODELS]:-}" ]]; then
            env_content+="OLLAMA_MODELS=${CONFIG_VALUES[OLLAMA_MODELS]}\n"
        fi
        
        if [[ -n "${CONFIG_VALUES[DEFAULT_MODEL]:-}" ]]; then
            env_content+="DEFAULT_MODEL=${CONFIG_VALUES[DEFAULT_MODEL]}\n"
        fi
        
        env_content+="\n"
    fi
    
    # Network
    env_content+="# Network Configuration\n"
    env_content+="DOCKER_NETWORK_NAME=${CONFIG_VALUES[DOCKER_NETWORK_NAME]}\n"
    env_content+="DOCKER_SUBNET=${CONFIG_VALUES[DOCKER_SUBNET]}\n"
    env_content+="DOCKER_GATEWAY=${CONFIG_VALUES[DOCKER_GATEWAY]}\n\n"
    
    # Write to file
    echo -e "$env_content" > "$ENV_FILE"
    
    return 0
}

save_config_summary() {
    local summary_file="${CONFIG_DIR}/setup-summary.txt"
    
    {
        echo "================================"
        echo "AI Platform Setup Summary"
        echo "================================"
        echo "Generated: $(date)"
        echo ""
        echo "Environment: ${CONFIG_VALUES[ENVIRONMENT]}"
        echo "Project: ${CONFIG_VALUES[COMPOSE_PROJECT_NAME]}"
        echo "Domain: ${CONFIG_VALUES[BASE_DOMAIN]}"
        echo ""
        echo "Services Installed:"
        [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]] && echo "  ✓ Ollama"
        [[ "${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}" == "true" ]] && echo "  ✓ Open WebUI"
        [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]] && echo "  ✓ n8n"
        [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]] && echo "  ✓ PostgreSQL"
        [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]] && echo "  ✓ Redis"
        [[ "${CONFIG_VALUES[INSTALL_NGINX]}" == "true" ]] && echo "  ✓ Nginx"
        echo ""
        echo "Access URLs:"
        [[ "${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}" == "true" ]] && echo "  Open WebUI: ${CONFIG_VALUES[WEBUI_URL]}"
        [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]] && echo "  n8n: ${CONFIG_VALUES[N8N_URL]}"
        [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]] && echo "  Ollama API: ${CONFIG_VALUES[OLLAMA_URL]}"
        echo ""
        echo "Credentials:"
        echo "  Admin Username: ${CONFIG_VALUES[ADMIN_USERNAME]}"
        echo "  Admin Password: ${CONFIG_VALUES[ADMIN_PASSWORD]}"
        echo ""
        echo "Configuration files:"
        echo "  .env: $ENV_FILE"
        echo "  docker-compose.yml: $DOCKER_COMPOSE_FILE"
        echo ""
    } > "$summary_file"
    
    log_success "Setup summary saved to: $summary_file"
}

#==============================================================================
# END OF PART 3/4
#==============================================================================
#!/bin/bash
################################################################################
# AI Platform Automation - System Setup Script
# Part 4/4: Docker Compose Generation, Deployment & Main Execution
################################################################################

#==============================================================================
# DOCKER COMPOSE GENERATION
#==============================================================================

generate_docker_compose() {
    local compose_file="$DOCKER_COMPOSE_FILE"
    
    cat > "$compose_file" << 'EOF'
version: '3.8'

networks:
  aiplatform:
    driver: bridge
    ipam:
      config:
        - subnet: ${DOCKER_SUBNET:-172.28.0.0/16}
          gateway: ${DOCKER_GATEWAY:-172.28.0.1}

volumes:
  postgres_data:
  redis_data:
  ollama_data:
  n8n_data:
  grafana_data:
  prometheus_data:

services:
EOF

    # Add Ollama service
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'

  ollama:
    image: ollama/ollama:latest
    container_name: ${COMPOSE_PROJECT_NAME}_ollama
    restart: unless-stopped
    networks:
      - aiplatform
    ports:
      - "${OLLAMA_PORT:-11434}:11434"
    volumes:
      - ollama_data:/root/.ollama
      - ${OLLAMA_MODELS_DIR:-./data/ollama/models}:/models
    environment:
      - OLLAMA_HOST=0.0.0.0:11434
      - OLLAMA_ORIGINS=*
    deploy:
      resources:
        limits:
          memory: ${OLLAMA_MAX_MEMORY:-8g}
          cpus: '${OLLAMA_MAX_CPUS:-4}'
EOF

        if [[ "${CONFIG_VALUES[ENABLE_GPU]}" == "true" ]] && [[ "${CONFIG_VALUES[GPU_TYPE]}" == "nvidia" ]]; then
            cat >> "$compose_file" << 'EOF'
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
EOF
        fi

        cat >> "$compose_file" << 'EOF'
    healthcheck:
      test: ["CMD", "ollama", "list"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
EOF
    fi

    # Add PostgreSQL service
    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'

  postgres:
    image: postgres:16-alpine
    container_name: ${COMPOSE_PROJECT_NAME}_postgres
    restart: unless-stopped
    networks:
      - aiplatform
    ports:
      - "${POSTGRES_PORT:-5432}:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./config/postgres/init:/docker-entrypoint-initdb.d
    environment:
      - POSTGRES_USER=${POSTGRES_USER:-aiplatform}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB:-aiplatform}
      - POSTGRES_INITDB_ARGS=-E UTF8 --locale=en_US.utf8
    command: >
      postgres
      -c max_connections=${POSTGRES_MAX_CONNECTIONS:-100}
      -c shared_buffers=${POSTGRES_SHARED_BUFFERS:-256MB}
      -c effective_cache_size=${POSTGRES_EFFECTIVE_CACHE:-1GB}
      -c maintenance_work_mem=64MB
      -c checkpoint_completion_target=0.9
      -c wal_buffers=16MB
      -c default_statistics_target=100
      -c random_page_cost=1.1
      -c effective_io_concurrency=200
      -c work_mem=4MB
      -c min_wal_size=1GB
      -c max_wal_size=4GB
    deploy:
      resources:
        limits:
          memory: ${POSTGRES_MAX_MEMORY:-2g}
          cpus: '2'
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-aiplatform}"]
      interval: 10s
      timeout: 5s
      retries: 5
EOF
    fi

    # Add Redis service
    if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'

  redis:
    image: redis:7-alpine
    container_name: ${COMPOSE_PROJECT_NAME}_redis
    restart: unless-stopped
    networks:
      - aiplatform
    ports:
      - "${REDIS_PORT:-6379}:6379"
    volumes:
      - redis_data:/data
    command: >
      redis-server
      --maxmemory ${REDIS_MAX_MEMORY:-512mb}
      --maxmemory-policy ${REDIS_EVICTION_POLICY:-allkeys-lru}
      --appendonly yes
      --appendfsync everysec
      --save 900 1
      --save 300 10
      --save 60 10000
    deploy:
      resources:
        limits:
          memory: ${REDIS_MAX_MEMORY:-512mb}
          cpus: '1'
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 3
EOF
    fi

    # Add Open WebUI service
    if [[ "${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: ${COMPOSE_PROJECT_NAME}_webui
    restart: unless-stopped
    networks:
      - aiplatform
    ports:
      - "${OPEN_WEBUI_PORT:-3000}:8080"
    volumes:
      - ${DATA_ROOT:-./data}/webui:/app/backend/data
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - WEBUI_SECRET_KEY=${WEBUI_JWT_SECRET}
      - WEBUI_NAME=AI Platform
      - DEFAULT_USER_ROLE=user
      - ENABLE_SIGNUP=${ENABLE_SIGNUP:-false}
      - ENABLE_API_KEY=true
EOF

        if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
            cat >> "$compose_file" << 'EOF'
      - DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
EOF
        fi

        cat >> "$compose_file" << 'EOF'
    depends_on:
      ollama:
        condition: service_healthy
EOF

        if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
            cat >> "$compose_file" << 'EOF'
      postgres:
        condition: service_healthy
EOF
        fi

        cat >> "$compose_file" << 'EOF'
    deploy:
      resources:
        limits:
          memory: 2g
          cpus: '2'
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF
    fi

    # Add n8n service
    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'

  n8n:
    image: n8nio/n8n:latest
    container_name: ${COMPOSE_PROJECT_NAME}_n8n
    restart: unless-stopped
    networks:
      - aiplatform
    ports:
      - "${N8N_PORT:-5678}:5678"
    volumes:
      - n8n_data:/home/node/.n8n
      - ${DATA_ROOT:-./data}/n8n:/files
    environment:
      - N8N_HOST=${BASE_DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=${N8N_PROTOCOL:-http}
      - WEBHOOK_URL=${N8N_WEBHOOK_URL:-http://localhost:5678}
      - GENERIC_TIMEZONE=${TIMEZONE:-UTC}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - EXECUTIONS_DATA_SAVE_ON_ERROR=all
      - EXECUTIONS_DATA_SAVE_ON_SUCCESS=all
      - EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS=true
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

        if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
            cat >> "$compose_file" << 'EOF'
      postgres:
        condition: service_healthy
EOF
        fi

        if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
            cat >> "$compose_file" << 'EOF'
      redis:
        condition: service_healthy
EOF
        fi

        cat >> "$compose_file" << 'EOF'
    deploy:
      resources:
        limits:
          memory: ${N8N_MAX_MEMORY:-2g}
          cpus: '2'
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF
    fi

    # Add Nginx service
    if [[ "${CONFIG_VALUES[INSTALL_NGINX]}" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'

  nginx:
    image: nginx:alpine
    container_name: ${COMPOSE_PROJECT_NAME}_nginx
    restart: unless-stopped
    networks:
      - aiplatform
    ports:
      - "${NGINX_HTTP_PORT:-80}:80"
      - "${NGINX_HTTPS_PORT:-443}:443"
    volumes:
      - ./config/nginx/conf.d:/etc/nginx/conf.d:ro
      - ./config/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./config/nginx/ssl:/etc/nginx/ssl:ro
      - ${DATA_ROOT:-./data}/nginx/cache:/var/cache/nginx
      - ${DATA_ROOT:-./data}/nginx/logs:/var/log/nginx
EOF

        if [[ "${CONFIG_VALUES[SSL_TYPE]}" == "letsencrypt" ]]; then
            cat >> "$compose_file" << 'EOF'
      - ./config/certbot/conf:/etc/letsencrypt:ro
      - ./config/certbot/www:/var/www/certbot:ro
EOF
        fi

        cat >> "$compose_file" << 'EOF'
    depends_on:
EOF

        if [[ "${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}" == "true" ]]; then
            cat >> "$compose_file" << 'EOF'
      - open-webui
EOF
        fi

        if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
            cat >> "$compose_file" << 'EOF'
      - n8n
EOF
        fi

        cat >> "$compose_file" << 'EOF'
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF
    fi

    # Add Certbot for Let's Encrypt
    if [[ "${CONFIG_VALUES[SSL_TYPE]}" == "letsencrypt" ]]; then
        cat >> "$compose_file" << 'EOF'

  certbot:
    image: certbot/certbot:latest
    container_name: ${COMPOSE_PROJECT_NAME}_certbot
    volumes:
      - ./config/certbot/conf:/etc/letsencrypt
      - ./config/certbot/www:/var/www/certbot
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;'"
    depends_on:
      - nginx
EOF
    fi

    # Add Prometheus
    if [[ "${CONFIG_VALUES[INSTALL_PROMETHEUS]}" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'

  prometheus:
    image: prom/prometheus:latest
    container_name: ${COMPOSE_PROJECT_NAME}_prometheus
    restart: unless-stopped
    networks:
      - aiplatform
    ports:
      - "${PROMETHEUS_PORT:-9090}:9090"
    volumes:
      - ./config/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--web.enable-lifecycle'
    deploy:
      resources:
        limits:
          memory: 1g
          cpus: '1'
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF
    fi

    # Add Grafana
    if [[ "${CONFIG_VALUES[INSTALL_GRAFANA]}" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'

  grafana:
    image: grafana/grafana:latest
    container_name: ${COMPOSE_PROJECT_NAME}_grafana
    restart: unless-stopped
    networks:
      - aiplatform
    ports:
      - "${GRAFANA_PORT:-3001}:3000"
    volumes:
      - grafana_data:/var/lib/grafana
      - ./config/grafana/provisioning:/etc/grafana/provisioning:ro
    environment:
      - GF_SECURITY_ADMIN_USER=${ADMIN_USERNAME}
      - GF_SECURITY_ADMIN_PASSWORD=${ADMIN_PASSWORD}
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource
      - GF_SERVER_ROOT_URL=%(protocol)s://%(domain)s:%(http_port)s/grafana/
EOF

        if [[ "${CONFIG_VALUES[INSTALL_PROMETHEUS]}" == "true" ]]; then
            cat >> "$compose_file" << 'EOF'
    depends_on:
      - prometheus
EOF
        fi

        cat >> "$compose_file" << 'EOF'
    deploy:
      resources:
        limits:
          memory: 512m
          cpus: '1'
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF
    fi

    # Add Portainer
    if [[ "${CONFIG_VALUES[INSTALL_PORTAINER]}" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'

  portainer:
    image: portainer/portainer-ce:latest
    container_name: ${COMPOSE_PROJECT_NAME}_portainer
    restart: unless-stopped
    networks:
      - aiplatform
    ports:
      - "${PORTAINER_PORT:-9443}:9443"
      - "${PORTAINER_HTTP_PORT:-9000}:9000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ${DATA_ROOT:-./data}/portainer:/data
    command: --admin-password-file /data/portainer_password
    deploy:
      resources:
        limits:
          memory: 256m
          cpus: '0.5'
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:9000/api/status"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF
    fi

    # Add Watchtower for auto-updates
    if [[ "${CONFIG_VALUES[INSTALL_WATCHTOWER]}" == "true" ]]; then
        cat >> "$compose_file" << 'EOF'

  watchtower:
    image: containrrr/watchtower:latest
    container_name: ${COMPOSE_PROJECT_NAME}_watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_POLL_INTERVAL=86400
      - WATCHTOWER_INCLUDE_RESTARTING=true
      - WATCHTOWER_ROLLING_RESTART=true
      - TZ=${TIMEZONE:-UTC}
EOF

        if [[ "${CONFIG_VALUES[NOTIFICATIONS_ENABLED]}" == "true" ]]; then
            if [[ "${CONFIG_VALUES[NOTIFY_EMAIL]}" == "true" ]]; then
                cat >> "$compose_file" << 'EOF'
      - WATCHTOWER_NOTIFICATIONS=email
      - WATCHTOWER_NOTIFICATION_EMAIL_FROM=${SMTP_FROM}
      - WATCHTOWER_NOTIFICATION_EMAIL_TO=${NOTIFICATION_EMAIL}
      - WATCHTOWER_NOTIFICATION_EMAIL_SERVER=${SMTP_SERVER}
      - WATCHTOWER_NOTIFICATION_EMAIL_SERVER_PORT=${SMTP_PORT}
      - WATCHTOWER_NOTIFICATION_EMAIL_SERVER_USER=${SMTP_USER}
      - WATCHTOWER_NOTIFICATION_EMAIL_SERVER_PASSWORD=${SMTP_PASSWORD}
EOF
            fi
        fi
    fi

    log_success "docker-compose.yml generated successfully"
    return 0
}

#==============================================================================
# NGINX CONFIGURATION GENERATION
#==============================================================================

generate_nginx_config() {
    local nginx_conf_dir="${CONFIG_DIR}/nginx"
    mkdir -p "${nginx_conf_dir}/conf.d"
    
    # Main nginx.conf
    cat > "${nginx_conf_dir}/nginx.conf" << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
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
    server_tokens off;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript 
               application/json application/javascript application/xml+rss 
               application/rss+xml font/truetype font/opentype 
               application/vnd.ms-fontobject image/svg+xml;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=api:10m rate=30r/s;

    # Include server configs
    include /etc/nginx/conf.d/*.conf;
}
EOF

    # Generate site configuration
    local site_conf="${nginx_conf_dir}/conf.d/default.conf"
    
    cat > "$site_conf" << EOF
# Upstream definitions
upstream ollama {
    server ollama:11434;
    keepalive 32;
}

upstream webui {
    server open-webui:8080;
    keepalive 32;
}

upstream n8n {
    server n8n:5678;
    keepalive 32;
}

# Health check endpoint
server {
    listen 80;
    server_name _;
    
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}

# HTTP server
server {
    listen 80;
    server_name ${CONFIG_VALUES[BASE_DOMAIN]};
    
    # Let's Encrypt challenge
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
EOF

    if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]]; then
        cat >> "$site_conf" << 'EOF'
    
    # Redirect to HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl http2;
    server_name ${BASE_DOMAIN};
    
    # SSL configuration
    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
EOF

        if [[ "${CONFIG_VALUES[ENABLE_HSTS]}" == "true" ]]; then
            cat >> "$site_conf" << EOF
    
    # HSTS
    add_header Strict-Transport-Security "max-age=${CONFIG_VALUES[HSTS_MAX_AGE]:-31536000}; includeSubDomains" always;
EOF
        fi
    fi

    # Add service proxies
    if [[ "${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}" == "true" ]]; then
        cat >> "$site_conf" << 'EOF'
    
    # Open WebUI
    location / {
        proxy_pass http://webui;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
        
        limit_req zone=general burst=20 nodelay;
    }
EOF
    fi

    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        cat >> "$site_conf" << 'EOF'
    
    # Ollama API
    location /ollama/ {
        proxy_pass http://ollama/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        proxy_read_timeout 600s;
        proxy_connect_timeout 75s;
        
        limit_req zone=api burst=50 nodelay;
    }
EOF
    fi

    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        cat >> "$site_conf" << 'EOF'
    
    # n8n
    location /n8n/ {
        proxy_pass http://n8n/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
        
        limit_req zone=general burst=20 nodelay;
    }
EOF
    fi

    cat >> "$site_conf" << 'EOF'
}
EOF

    log_success "Nginx configuration generated"
    return 0
}

#==============================================================================
# BACKUP SCRIPT GENERATION
#==============================================================================

generate_backup_scripts() {
    local backup_script="${SCRIPT_DIR}/backup.sh"
    
    cat > "$backup_script" << 'BACKUP_EOF'
#!/bin/bash
################################################################################
# AI Platform Backup Script
# Generated automatically - do not edit manually
################################################################################

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-./backups}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_NAME="aiplatform_backup_${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

echo "Starting backup: ${BACKUP_NAME}"

# Create backup directory
mkdir -p "$BACKUP_PATH"

# Backup configurations
echo "Backing up configurations..."
cp -r ./config "$BACKUP_PATH/"

# Backup .env
cp .env "$BACKUP_PATH/"

# Backup PostgreSQL
if docker ps --format '{{.Names}}' | grep -q postgres; then
    echo "Backing up PostgreSQL..."
    docker exec aiplatform_postgres pg_dumpall -U ${POSTGRES_USER:-aiplatform} > "$BACKUP_PATH/postgres.sql"
fi

# Backup volumes
echo "Backing up Docker volumes..."
docker run --rm \
    -v aiplatform_postgres_data:/data \
    -v "$BACKUP_PATH:/backup" \
    alpine tar czf /backup/postgres_data.tar.gz -C /data .

# Create archive
echo "Creating backup archive..."
cd "$BACKUP_DIR"
tar czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"
rm -rf "$BACKUP_NAME"

echo "Backup completed: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"

# Cleanup old backups (keep last 7)
echo "Cleaning up old backups..."
ls -t aiplatform_backup_*.tar.gz | tail -n +8 | xargs -r rm --

echo "Backup process finished successfully"
BACKUP_EOF

    chmod +x "$backup_script"
    
    # Generate restore script
    local restore_script="${SCRIPT_DIR}/restore.sh"
    
    cat > "$restore_script" << 'RESTORE_EOF'
#!/bin/bash
################################################################################
# AI Platform Restore Script
# Generated automatically - do not edit manually
################################################################################

set -euo pipefail

if [ $# -eq 0 ]; then
    echo "Usage: $0 <backup_file.tar.gz>"
    echo ""
    echo "Available backups:"
    ls -lh ./backups/aiplatform_backup_*.tar.gz 2>/dev/null || echo "No backups found"
    exit 1
fi

BACKUP_FILE="$1"
RESTORE_DIR="./restore_temp"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo "WARNING: This will restore from backup and may overwrite current data!"
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Restore cancelled"
    exit 0
fi

# Extract backup
echo "Extracting backup..."
mkdir -p "$RESTORE_DIR"
tar xzf "$BACKUP_FILE" -C "$RESTORE_DIR"

BACKUP_NAME=$(basename "$BACKUP_FILE" .tar.gz)
BACKUP_PATH="$RESTORE_DIR/$BACKUP_NAME"

# Stop services
echo "Stopping services..."
docker-compose down

# Restore configurations
echo "Restoring configurations..."
cp -r "$BACKUP_PATH/config/"* ./config/
cp "$BACKUP_PATH/.env" ./

# Restore PostgreSQL
if [ -f "$BACKUP_PATH/postgres.sql" ]; then
    echo "Restoring PostgreSQL..."
    docker-compose up -d postgres
    sleep 10
    docker exec -i aiplatform_postgres psql -U ${POSTGRES_USER:-aiplatform} < "$BACKUP_PATH/postgres.sql"
fi

# Cleanup
echo "Cleaning up..."
rm -rf "$RESTORE_DIR"

# Restart services
echo "Starting services..."
docker-compose up -d

echo "Restore completed successfully"
echo "Please verify your services are running correctly"
RESTORE_EOF

    chmod +x "$restore_script"
    
    log_success "Backup and restore scripts generated"
    return 0
}

#==============================================================================
# DEPLOYMENT FUNCTIONS
#==============================================================================

deploy_stack() {
    print_header "Deploying AI Platform"
    
    log_step "Starting deployment process..."
    
    # Validate Docker
    if ! command -v docker &>/dev/null; then
        log_error "Docker is not installed"
        return 1
    fi
    
    if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null; then
        log_error "Docker Compose is not installed"
        return 1
    fi
    
    # Load environment
    if [ -f "$ENV_FILE" ]; then
        set -a
        source "$ENV_FILE"
        set +a
    fi
    
    # Pull images
    log_step "Pulling Docker images..."
    if docker compose version &>/dev/null; then
        docker compose -f "$DOCKER_COMPOSE_FILE" pull
    else
        docker-compose -f "$DOCKER_COMPOSE_FILE" pull
    fi
    
    # Create network
    log_step "Creating Docker network..."
    docker network create "${CONFIG_VALUES[DOCKER_NETWORK_NAME]}" 2>/dev/null || true
    
    # Start services
    log_step "Starting services..."
    if docker compose version &>/dev/null; then
        docker compose -f "$DOCKER_COMPOSE_FILE" up -d
    else
        docker-compose -f "$DOCKER_COMPOSE_FILE" up -d
    fi
    
    # Wait for services to be healthy
    log_step "Waiting for services to become healthy..."
    local max_wait=300
    local waited=0
    
    while [ $waited -lt $max_wait ]; do
        local unhealthy=$(docker ps --filter health=unhealthy --format '{{.Names}}' | wc -l)
        local starting=$(docker ps --filter health=starting --format '{{.Names}}' | wc -l)
        
        if [ "$unhealthy" -eq 0 ] && [ "$starting" -eq 0 ]; then
            log_success "All services are healthy"
            break
        fi
        
        echo -n "."
        sleep 5
        waited=$((waited + 5))
    done
    
    if [ $waited -ge $max_wait ]; then
        log_warning "Timeout waiting for services. Check 'docker ps' for status"
    fi
    
    # Download Ollama models if configured
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]] && [[ -n "${CONFIG_VALUES[OLLAMA_MODELS]:-}" ]]; then
        if [[ "${CONFIG_VALUES[MODEL_DOWNLOAD_TIMING]}" == "During setup" ]]; then
            download_ollama_models
        fi
    fi
    
    log_success "Deployment completed successfully"
    return 0
}

download_ollama_models() {
    log_step "Downloading Ollama models..."
    
    IFS=' ' read -ra models <<< "${CONFIG_VALUES[OLLAMA_MODELS]}"
    
    for model in "${models[@]}"; do
        log_info "Downloading model: $model"
        if ! docker exec aiplatform_ollama ollama pull "$model"; then
            log_warning "Failed to download model: $model"
        else
            log_success "Model downloaded: $model"
        fi
    done
}

#==============================================================================
# POST-DEPLOYMENT FUNCTIONS
#==============================================================================

post_deployment_setup() {
    print_header "Post-Deployment Setup"
    
    # Set Portainer password if installed
    if [[ "${CONFIG_VALUES[INSTALL_PORTAINER]}" == "true" ]]; then
        log_step "Setting up Portainer..."
        echo -n "${CONFIG_VALUES[ADMIN_PASSWORD]}" | docker run --rm -i portainer/portainer-ce htpasswd -nbi admin > "${CONFIG_VALUES[DATA_ROOT]}/portainer/portainer_password"
    fi
    
    # Initialize SSL if Let's Encrypt
    if [[ "${CONFIG_VALUES[SSL_TYPE]}" == "letsencrypt" ]]; then
        log_step "Initializing Let's Encrypt SSL..."
        
        local staging_arg=""
        if [[ "${CONFIG_VALUES[LETSENCRYPT_STAGING]}" == "true" ]]; then
            staging_arg="--staging"
        fi
        
        docker run --rm \
            -v "${CONFIG_DIR}/certbot/conf:/etc/letsencrypt" \
            -v "${CONFIG_DIR}/certbot/www:/var/www/certbot" \
            certbot/certbot certonly \
            --webroot \
            --webroot-path=/var/www/certbot \
            --email "${CONFIG_VALUES[SSL_EMAIL]}" \
            --agree-tos \
            --no-eff-email \
            $staging_arg \
            -d "${CONFIG_VALUES[BASE_DOMAIN]}"
        
        # Reload Nginx
        docker exec aiplatform_nginx nginx -s reload
    fi
    
    log_success "Post-deployment setup completed"
}

#==============================================================================
# DISPLAY FINAL INFORMATION
#==============================================================================

display_completion_info() {
    clear
    print_header "Setup Complete! 🎉"
    
    echo
    print_section_break
    echo "✓ AI Platform has been successfully deployed!"
    print_section_break
    echo
    
    echo "ACCESS INFORMATION:"
    echo "==================="
    
    local protocol="http"
    if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]]; then
        protocol="https"
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}" == "true" ]]; then
        echo "🌐 Open WebUI:    ${protocol}://${CONFIG_VALUES[BASE_DOMAIN]}"
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        echo "🔧 n8n:           ${protocol}://${CONFIG_VALUES[BASE_DOMAIN]}/n8n"
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        echo "🤖 Ollama API:    ${protocol}://${CONFIG_VALUES[BASE_DOMAIN]}/ollama"
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_PORTAINER]}" == "true" ]]; then
        echo "🐳 Portainer:     https://${CONFIG_VALUES[BASE_DOMAIN]}:${CONFIG_VALUES[PORTAINER_PORT]}"
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_GRAFANA]}" == "true" ]]; then
        echo "📊 Grafana:       ${protocol}://${CONFIG_VALUES[BASE_DOMAIN]}/grafana"
    fi
    
    echo
    echo "CREDENTIALS:"
    echo "============"
    echo "Username: ${CONFIG_VALUES[ADMIN_USERNAME]}"
    echo "Password: ${CONFIG_VALUES[ADMIN_PASSWORD]}"
    echo
    
    if [[ -n "${CONFIG_VALUES[OLLAMA_MODELS]:-}" ]]; then
        echo "INSTALLED MODELS:"
        echo "================="
        for model in ${CONFIG_VALUES[OLLAMA_MODELS]}; do
            echo "  • $model"
        done
        echo
    fi
    
    echo "USEFUL COMMANDS:"
    echo "================"
    echo "View logs:        docker-compose logs -f [service]"
    echo "Restart services: docker-compose restart"
    echo "Stop platform:    docker-compose down"
    echo "Start platform:   docker-compose up -d"
    echo "Backup data:      ./scripts/backup.sh"
    echo "Restore data:     ./scripts/restore.sh <backup_file>"
    echo
    
    echo "CONFIGURATION FILES:"
    echo "===================="
    echo "Environment:      $ENV_FILE"
    echo "Docker Compose:   $DOCKER_COMPOSE_FILE"
    echo "Setup Summary:    ${CONFIG_DIR}/setup-summary.txt"
    echo "Logs:             $LOG_FILE"
    echo
    
    echo "NEXT STEPS:"
    echo "==========="
    echo "1. Visit Open WebUI and create your first account"
    echo "2. Configure n8n workflows if installed"
    echo "3. Review Grafana dashboards if monitoring is enabled"
    echo "4. Set up regular backups (backup.sh)"
    echo "5. Review security settings and firewall rules"
    echo
    
    if [[ "${CONFIG_VALUES[ENABLE_SSL]}" != "true" ]]; then
        echo "⚠️  WARNING: SSL is not enabled. Consider enabling it for production use."
        echo
    fi
    
    print_section_break
    echo "Thank you for using AI Platform Automation!"
    echo "For support and documentation, visit: https://github.com/yourusername/ai-platform"
    print_section_break
    echo
}

#==============================================================================
# MAIN FUNCTION
#==============================================================================

main() {
    # Trap errors
    trap 'log_error "Script failed at line $LINENO"' ERR
    
    # Initialize
    initialize_logging
    
    # Run wizard steps
    step_01_welcome
    step_02_environment
    step_03_services
    step_04_domain_ports
    step_05_database
    step_06_data_storage
    step_07_monitoring
    step_08_backup
    step_09_timezone
    step_10_resources
    step_11_ssl
    step_12_security
    step_13_models
    step_14_network
    step_15_performance
    step_16_maintenance
    step_17_notifications
    step_18_integrations
    
    # Review and generate
    while true; do
        step_19_review
        local review_result=$?
        
        if [ $review_result -eq 2 ]; then
            # Restart wizard
            continue
        elif [ $review_result -eq 0 ]; then
            break
        else
            log_error "Configuration review failed"
            exit 1
        fi
    done
    
    step_20_generate_configs
    
    # Deploy
    if prompt_yes_no "Deploy the platform now?" "y"; then
        deploy_stack
        post_deployment_setup
        display_completion_info
    else
        log_info "Configuration saved. Run 'docker-compose up -d' when ready to deploy"
        echo
        echo "Configuration files have been generated:"
        echo "  • $ENV_FILE"
        echo "  • $DOCKER_COMPOSE_FILE"
        echo
        echo "To deploy later, run: docker-compose up -d"
    fi
    
    log_success "Setup script completed successfully"
}

#==============================================================================
# SCRIPT EXECUTION
#==============================================================================

# Run main function
main "$@"

exit 0

#==============================================================================
# END OF SCRIPT
#==============================================================================
