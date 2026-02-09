#!/bin/bash
################################################################################
# AI Platform Automation - System Setup Script
# Part 1/4: Foundation, Logging, Utilities, Validation
# Version: 2.0.0
################################################################################

set -euo pipefail

#==============================================================================
# GLOBAL VARIABLES
#==============================================================================

# Script directory detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Directories
CONFIG_DIR="${PROJECT_ROOT}/config"
DATA_DIR="${PROJECT_ROOT}/data"
LOGS_DIR="${PROJECT_ROOT}/logs"
BACKUP_DIR="${PROJECT_ROOT}/backups"

# Files
ENV_FILE="${PROJECT_ROOT}/.env"
DOCKER_COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"
LOG_FILE="${LOGS_DIR}/setup_$(date +%Y%m%d_%H%M%S).log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Configuration storage
declare -A CONFIG_VALUES=(
    [ENVIRONMENT]="production"
    [DATA_ROOT]="${PROJECT_ROOT}/data"
    [LOGS_ROOT]="${PROJECT_ROOT}/logs"
    [BACKUP_ROOT]="${PROJECT_ROOT}/backups"
    [COMPOSE_PROJECT_NAME]="aiplatform"
    [BASE_DOMAIN]="localhost"
    [TIMEZONE]="UTC"
    [DOCKER_NETWORK_NAME]="aiplatform"
    [DOCKER_SUBNET]="172.28.0.0/16"
    [DOCKER_GATEWAY]="172.28.0.1"
    
    # Service toggles
    [INSTALL_OLLAMA]="true"
    [INSTALL_OPEN_WEBUI]="true"
    [INSTALL_N8N]="false"
    [INSTALL_POSTGRES]="false"
    [INSTALL_REDIS]="false"
    [INSTALL_NGINX]="false"
    [INSTALL_PROMETHEUS]="false"
    [INSTALL_GRAFANA]="false"
    [INSTALL_PORTAINER]="false"
    [INSTALL_WATCHTOWER]="false"
    
    # Ports
    [OLLAMA_PORT]="11434"
    [OPEN_WEBUI_PORT]="3000"
    [N8N_PORT]="5678"
    [POSTGRES_PORT]="5432"
    [REDIS_PORT]="6379"
    [NGINX_HTTP_PORT]="80"
    [NGINX_HTTPS_PORT]="443"
    [PROMETHEUS_PORT]="9090"
    [GRAFANA_PORT]="3001"
    [PORTAINER_PORT]="9443"
    [PORTAINER_HTTP_PORT]="9000"
    
    # Resources
    [OLLAMA_MAX_MEMORY]="8g"
    [OLLAMA_MAX_CPUS]="4"
    [POSTGRES_MAX_MEMORY]="2g"
    [REDIS_MAX_MEMORY]="512mb"
    [N8N_MAX_MEMORY]="2g"
    
    # Security
    [ENABLE_SSL]="false"
    [SSL_TYPE]="none"
    [ENABLE_HSTS]="false"
    [HSTS_MAX_AGE]="31536000"
    
    # Backups
    [BACKUP_ENABLED]="true"
    [BACKUP_RETENTION_DAYS]="7"
    [BACKUP_SCHEDULE]="0 2 * * *"
    
    # GPU
    [ENABLE_GPU]="false"
    [GPU_TYPE]="none"
    
    # Notifications
    [NOTIFICATIONS_ENABLED]="false"
    [NOTIFY_EMAIL]="false"
    [NOTIFY_SLACK]="false"
)

#==============================================================================
# LOGGING FUNCTIONS - MUST BE FIRST
#==============================================================================

# Create log directory first
create_log_directory() {
    if [ ! -d "$LOGS_DIR" ]; then
        mkdir -p "$LOGS_DIR" 2>/dev/null || {
            echo "ERROR: Cannot create logs directory: $LOGS_DIR" >&2
            echo "Attempting to use /tmp for logs..." >&2
            LOGS_DIR="/tmp/aiplatform_logs"
            mkdir -p "$LOGS_DIR"
            LOG_FILE="${LOGS_DIR}/setup_$(date +%Y%m%d_%H%M%S).log"
        }
    fi
    
    # Create log file
    touch "$LOG_FILE" 2>/dev/null || {
        echo "ERROR: Cannot create log file: $LOG_FILE" >&2
        LOG_FILE="/tmp/aiplatform_setup_$(date +%Y%m%d_%H%M%S).log"
        touch "$LOG_FILE"
    }
}

# Initialize logging - MUST BE CALLED EARLY
initialize_logging() {
    create_log_directory
    
    # Log script start
    {
        echo "========================================"
        echo "AI Platform Setup Script"
        echo "========================================"
        echo "Started: $(date)"
        echo "User: $USER"
        echo "Hostname: $(hostname)"
        echo "Log file: $LOG_FILE"
        echo "========================================"
        echo ""
    } | tee -a "$LOG_FILE"
}

# Log with timestamp
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${level}] ${timestamp} - ${message}" | tee -a "$LOG_FILE"
}

log_info() {
    log_message "INFO" "$@"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}✗${NC} $*" | tee -a "$LOG_FILE" >&2
}

log_step() {
    echo -e "${BLUE}➜${NC} $*" | tee -a "$LOG_FILE"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log_message "DEBUG" "$@"
    fi
}

#==============================================================================
# DISPLAY FUNCTIONS
#==============================================================================

print_header() {
    local title="$1"
    echo | tee -a "$LOG_FILE"
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}" | tee -a "$LOG_FILE"
    printf "${CYAN}║${NC} %-60s ${CYAN}║${NC}\n" "$title" | tee -a "$LOG_FILE"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
}

print_step_header() {
    local step_num="$1"
    local step_title="$2"
    echo | tee -a "$LOG_FILE"
    echo -e "${MAGENTA}┌──────────────────────────────────────────────────────────────┐${NC}" | tee -a "$LOG_FILE"
    printf "${MAGENTA}│${NC} Step %2d/20: %-46s ${MAGENTA}│${NC}\n" "$step_num" "$step_title" | tee -a "$LOG_FILE"
    echo -e "${MAGENTA}└──────────────────────────────────────────────────────────────┘${NC}" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
}

print_section_break() {
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}" | tee -a "$LOG_FILE"
}

#==============================================================================
# INPUT VALIDATION FUNCTIONS
#==============================================================================

is_valid_domain() {
    local domain="$1"
    
    # Allow localhost
    if [[ "$domain" == "localhost" ]]; then
        return 0
    fi
    
    # Basic domain validation regex
    if [[ "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    
    return 1
}

is_valid_email() {
    local email="$1"
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    return 1
}

is_valid_port() {
    local port="$1"
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    fi
    return 1
}

is_port_available() {
    local port="$1"
    if command -v netstat &>/dev/null; then
        if netstat -tuln | grep -q ":${port} "; then
            return 1
        fi
    elif command -v ss &>/dev/null; then
        if ss -tuln | grep -q ":${port} "; then
            return 1
        fi
    fi
    return 0
}

is_valid_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [ "$i" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

is_valid_subnet() {
    local subnet="$1"
    if [[ "$subnet" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        return 0
    fi
    return 1
}

#==============================================================================
# USER INPUT FUNCTIONS
#==============================================================================

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local answer
    
    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
    while true; do
        read -rp "$prompt" answer
        answer=${answer:-$default}
        answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')
        
        case "$answer" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local answer
    
    read -rp "$prompt [$default]: " answer
    echo "${answer:-$default}"
}

prompt_required() {
    local prompt="$1"
    local answer
    
    while true; do
        read -rp "$prompt: " answer
        if [[ -n "$answer" ]]; then
            echo "$answer"
            return 0
        fi
        log_error "This field is required"
    done
}

prompt_choice() {
    local prompt="$1"
    shift
    local options=("$@")
    local choice
    
    echo "$prompt"
    for i in "${!options[@]}"; do
        echo "  $((i+1))) ${options[$i]}"
    done
    
    while true; do
        read -rp "Select option [1-${#options[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
            echo "${options[$((choice-1))]}"
            return 0
        fi
        log_error "Invalid choice. Please select 1-${#options[@]}"
    done
}

prompt_multiselect() {
    local prompt="$1"
    shift
    local options=("$@")
    local selected=()
    
    echo "$prompt"
    echo "(Enter space-separated numbers, or 'done' when finished)"
    
    for i in "${!options[@]}"; do
        echo "  $((i+1))) ${options[$i]}"
    done
    
    while true; do
        read -rp "Select options: " -a choices
        
        if [[ "${choices[0]}" == "done" ]]; then
            break
        fi
        
        for choice in "${choices[@]}"; do
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
                selected+=("${options[$((choice-1))]}")
            fi
        done
        
        if [ ${#selected[@]} -gt 0 ]; then
            break
        fi
    done
    
    echo "${selected[@]}"
}

#==============================================================================
# SYSTEM CHECK FUNCTIONS
#==============================================================================

check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run with sudo"
        log_info "Usage: sudo $0"
        exit 1
    fi
}

check_os() {
    if [ ! -f /etc/os-release ]; then
        log_error "Cannot determine OS. /etc/os-release not found"
        return 1
    fi
    
    source /etc/os-release
    
    log_info "Detected OS: $NAME $VERSION"
    
    case "$ID" in
        ubuntu|debian|centos|rhel|fedora|rocky|almalinux)
            log_success "OS is supported"
            return 0
            ;;
        *)
            log_warning "OS may not be fully supported: $ID"
            if ! prompt_yes_no "Continue anyway?" "n"; then
                return 1
            fi
            ;;
    esac
}

check_dependencies() {
    local missing_deps=()
    local required_commands=("curl" "wget" "tar" "gzip" "git")
    
    log_step "Checking required dependencies..."
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_warning "Missing dependencies: ${missing_deps[*]}"
        
        if prompt_yes_no "Install missing dependencies?" "y"; then
            install_dependencies "${missing_deps[@]}"
        else
            log_error "Cannot proceed without required dependencies"
            return 1
        fi
    else
        log_success "All dependencies satisfied"
    fi
    
    return 0
}

install_dependencies() {
    local packages=("$@")
    
    log_step "Installing dependencies: ${packages[*]}"
    
    if command -v apt-get &>/dev/null; then
        apt-get update
        apt-get install -y "${packages[@]}"
    elif command -v yum &>/dev/null; then
        yum install -y "${packages[@]}"
    elif command -v dnf &>/dev/null; then
        dnf install -y "${packages[@]}"
    else
        log_error "Cannot determine package manager"
        return 1
    fi
    
    log_success "Dependencies installed"
}

check_docker() {
    log_step "Checking Docker installation..."
    
    if ! command -v docker &>/dev/null; then
        log_warning "Docker is not installed"
        if prompt_yes_no "Install Docker now?" "y"; then
            install_docker
        else
            log_error "Docker is required. Cannot proceed."
            return 1
        fi
    else
        local docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
        log_success "Docker is installed: $docker_version"
    fi
    
    # Check Docker Compose
    if ! docker compose version &>/dev/null && ! command -v docker-compose &>/dev/null; then
        log_warning "Docker Compose is not installed"
        if prompt_yes_no "Install Docker Compose?" "y"; then
            install_docker_compose
        else
            log_error "Docker Compose is required. Cannot proceed."
            return 1
        fi
    else
        log_success "Docker Compose is installed"
    fi
    
    # Check Docker service
    if ! systemctl is-active --quiet docker; then
        log_warning "Docker service is not running"
        systemctl start docker
        systemctl enable docker
        log_success "Docker service started"
    fi
    
    return 0
}

install_docker() {
    log_step "Installing Docker..."
    
    # Install using official script
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    rm /tmp/get-docker.sh
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    # Add current user to docker group if not root
    if [ -n "${SUDO_USER:-}" ]; then
        usermod -aG docker "$SUDO_USER"
        log_info "Added $SUDO_USER to docker group (re-login required)"
    fi
    
    log_success "Docker installed successfully"
}

install_docker_compose() {
    log_step "Installing Docker Compose..."
    
    # Docker Compose v2 is now included with Docker
    # Just verify it's available
    if docker compose version &>/dev/null; then
        log_success "Docker Compose v2 is available"
        return 0
    fi
    
    # Fallback to installing standalone docker-compose
    local compose_version="2.24.0"
    curl -L "https://github.com/docker/compose/releases/download/v${compose_version}/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
    
    chmod +x /usr/local/bin/docker-compose
    
    log_success "Docker Compose installed successfully"
}

check_disk_space() {
    local min_space_gb=20
    local data_dir="${CONFIG_VALUES[DATA_ROOT]}"
    
    log_step "Checking disk space..."
    
    local available_space=$(df -BG "$data_dir" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [ -z "$available_space" ]; then
        log_warning "Could not determine available disk space"
        return 0
    fi
    
    if [ "$available_space" -lt "$min_space_gb" ]; then
        log_warning "Low disk space: ${available_space}GB available (${min_space_gb}GB recommended)"
        if ! prompt_yes_no "Continue anyway?" "n"; then
            return 1
        fi
    else
        log_success "Sufficient disk space: ${available_space}GB available"
    fi
    
    return 0
}

check_memory() {
    local min_memory_gb=8
    
    log_step "Checking system memory..."
    
    local total_memory=$(free -g | awk '/^Mem:/ {print $2}')
    
    if [ "$total_memory" -lt "$min_memory_gb" ]; then
        log_warning "Low system memory: ${total_memory}GB (${min_memory_gb}GB recommended)"
        if ! prompt_yes_no "Continue anyway?" "n"; then
            return 1
        fi
    else
        log_success "Sufficient memory: ${total_memory}GB available"
    fi
    
    return 0
}

#==============================================================================
# DIRECTORY SETUP FUNCTIONS
#==============================================================================

create_directory_structure() {
    log_step "Creating directory structure..."
    
    local dirs=(
        "$CONFIG_DIR"
        "$DATA_DIR"
        "$LOGS_DIR"
        "$BACKUP_DIR"
        "${CONFIG_DIR}/nginx"
        "${CONFIG_DIR}/nginx/conf.d"
        "${CONFIG_DIR}/nginx/ssl"
        "${CONFIG_DIR}/postgres"
        "${CONFIG_DIR}/postgres/init"
        "${CONFIG_DIR}/prometheus"
        "${CONFIG_DIR}/grafana"
        "${CONFIG_DIR}/grafana/provisioning"
        "${CONFIG_DIR}/certbot"
        "${CONFIG_DIR}/certbot/conf"
        "${CONFIG_DIR}/certbot/www"
        "${DATA_DIR}/ollama"
        "${DATA_DIR}/ollama/models"
        "${DATA_DIR}/webui"
        "${DATA_DIR}/n8n"
        "${DATA_DIR}/portainer"
        "${DATA_DIR}/nginx"
        "${DATA_DIR}/nginx/cache"
        "${DATA_DIR}/nginx/logs"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir" || {
                log_error "Failed to create directory: $dir"
                return 1
            }
        fi
    done
    
    # Set permissions
    if [ -n "${SUDO_USER:-}" ]; then
        chown -R "$SUDO_USER:$SUDO_USER" "$PROJECT_ROOT"
    fi
    
    log_success "Directory structure created"
    return 0
}

#==============================================================================
# SECRET GENERATION FUNCTIONS
#==============================================================================

generate_secret() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
}

generate_password() {
    local length="${1:-16}"
    openssl rand -base64 48 | tr -d "=+/" | cut -c1-"$length"
}

generate_jwt_secret() {
    openssl rand -hex 32
}

#==============================================================================
# GPU DETECTION FUNCTIONS
#==============================================================================

detect_nvidia_gpu() {
    if command -v nvidia-smi &>/dev/null; then
        if nvidia-smi &>/dev/null; then
            return 0
        fi
    fi
    return 1
}

detect_amd_gpu() {
    if command -v rocm-smi &>/dev/null; then
        if rocm-smi &>/dev/null; then
            return 0
        fi
    fi
    return 1
}

#==============================================================================
# END OF PART 1/4
#==============================================================================
#!/bin/bash
################################################################################
# AI Platform Automation - System Setup Script  
# Part 2/4: Configuration Wizard Steps 1-14 (CORRECTED)
################################################################################

#==============================================================================
# STEP 1: WELCOME & SYSTEM CHECKS
#==============================================================================

step_01_welcome() {
    clear
    print_header "AI Platform Automation - Setup Wizard"
    
    cat << 'EOF'
Welcome to the AI Platform Setup Wizard!

This wizard will guide you through configuring:
  • Local AI services (Ollama, Open WebUI)
  • Workflow automation (n8n)
  • Database & caching (PostgreSQL, Redis)
  • Reverse proxy & SSL (Nginx/Traefik/Caddy)
  • Monitoring & observability (Prometheus, Grafana)
  • LLM provider configuration (Local/External/Hybrid)
  • Vector databases (Qdrant/Chroma/Weaviate)
  • Authentication providers (Local/LDAP/OAuth/SAML)

The wizard has 27 interactive steps and takes ~15-20 minutes.

Requirements:
  • Linux system (Ubuntu 20.04+, Debian 11+, RHEL 8+)
  • 8GB+ RAM (16GB+ recommended)
  • 50GB+ free disk space
  • Root/sudo access
  • Docker 24.0+ & Docker Compose 2.0+

EOF

    if ! prompt_yes_no "Ready to begin?" "y"; then
        log_info "Setup cancelled by user"
        exit 0
    fi
    
    # System checks
    log_step "Running system checks..."
    check_os || exit 1
    check_docker || exit 1
    check_dependencies || exit 1
    check_disk_space || exit 1
    check_memory || exit 1
    
    log_success "System checks passed"
}

#==============================================================================
# STEP 2: DEPLOYMENT ENVIRONMENT
#==============================================================================

step_02_environment() {
    print_step_header 1 "Deployment Environment"
    
    cat << 'EOF'
Select your deployment environment:

  1) Production  - Full security, SSL, monitoring, backups
  2) Staging     - Similar to production, relaxed security
  3) Development - Minimal security, local access only
  4) Testing     - Ephemeral, no persistence

EOF

    local env=$(prompt_choice "Environment:" "Production" "Staging" "Development" "Testing")
    CONFIG_VALUES[ENVIRONMENT]=$(echo "$env" | tr '[:upper:]' '[:lower:]')
    
    log_info "Environment: ${CONFIG_VALUES[ENVIRONMENT]}"
}

#==============================================================================
# STEP 3: CORE SERVICES SELECTION
#==============================================================================

step_03_core_services() {
    print_step_header 2 "Core Services Selection"
    
    cat << 'EOF'
Select which core services to install:

Essential Services:
  • Ollama        - Local LLM inference engine
  • Open WebUI    - Web interface for LLMs

Optional Services:
  • n8n           - Workflow automation
  • PostgreSQL    - Relational database
  • Redis         - In-memory cache
  • Portainer     - Docker GUI management

EOF

    # Ollama (recommended)
    if prompt_yes_no "Install Ollama (local LLM)?" "y"; then
        CONFIG_VALUES[INSTALL_OLLAMA]="true"
    else
        CONFIG_VALUES[INSTALL_OLLAMA]="false"
        log_warning "Ollama disabled - you'll need external LLM providers"
    fi
    
    # Open WebUI
    if prompt_yes_no "Install Open WebUI?" "y"; then
        CONFIG_VALUES[INSTALL_OPEN_WEBUI]="true"
    else
        CONFIG_VALUES[INSTALL_OPEN_WEBUI]="false"
    fi
    
    # n8n
    if prompt_yes_no "Install n8n (workflow automation)?" "n"; then
        CONFIG_VALUES[INSTALL_N8N]="true"
    else
        CONFIG_VALUES[INSTALL_N8N]="false"
    fi
    
    # PostgreSQL
    if prompt_yes_no "Install PostgreSQL database?" "n"; then
        CONFIG_VALUES[INSTALL_POSTGRES]="true"
    else
        CONFIG_VALUES[INSTALL_POSTGRES]="false"
    fi
    
    # Redis
    if prompt_yes_no "Install Redis cache?" "n"; then
        CONFIG_VALUES[INSTALL_REDIS]="true"
    else
        CONFIG_VALUES[INSTALL_REDIS]="false"
    fi
    
    # Portainer
    if prompt_yes_no "Install Portainer (Docker GUI)?" "n"; then
        CONFIG_VALUES[INSTALL_PORTAINER]="true"
    else
        CONFIG_VALUES[INSTALL_PORTAINER]="false"
    fi
    
    log_info "Core services configured"
}

#==============================================================================
# STEP 4: REVERSE PROXY SELECTION
#==============================================================================

step_04_reverse_proxy() {
    print_step_header 3 "Reverse Proxy Selection"
    
    cat << 'EOF'
Choose a reverse proxy for routing and SSL termination:

  1) Nginx    - Traditional, proven, highly configurable
  2) Traefik  - Modern, auto-discovery, Let's Encrypt built-in
  3) Caddy    - Simple, automatic HTTPS, minimal config
  4) None     - Direct port access (dev/testing only)

EOF

    local proxy=$(prompt_choice "Reverse proxy:" "Nginx" "Traefik" "Caddy" "None")
    
    case "$proxy" in
        "Nginx")
            CONFIG_VALUES[INSTALL_NGINX]="true"
            CONFIG_VALUES[PROXY_TYPE]="nginx"
            ;;
        "Traefik")
            CONFIG_VALUES[INSTALL_TRAEFIK]="true"
            CONFIG_VALUES[PROXY_TYPE]="traefik"
            ;;
        "Caddy")
            CONFIG_VALUES[INSTALL_CADDY]="true"
            CONFIG_VALUES[PROXY_TYPE]="caddy"
            ;;
        "None")
            CONFIG_VALUES[PROXY_TYPE]="none"
            log_warning "No reverse proxy - services exposed on direct ports"
            ;;
    esac
    
    log_info "Proxy: ${CONFIG_VALUES[PROXY_TYPE]}"
}

#==============================================================================
# STEP 5: DOMAIN & NETWORK CONFIGURATION
#==============================================================================

step_05_domain_network() {
    print_step_header 4 "Domain & Network Configuration"
    
    cat << 'EOF'
Configure your domain and network settings.

Examples:
  • Production: ai.example.com
  • Development: localhost
  • LAN access: 192.168.1.100

EOF

    while true; do
        local domain=$(prompt_with_default "Base domain" "localhost")
        
        if [[ "$domain" == "localhost" ]]; then
            CONFIG_VALUES[BASE_DOMAIN]="localhost"
            CONFIG_VALUES[WEBUI_URL]="http://localhost:3000"
            CONFIG_VALUES[OLLAMA_URL]="http://localhost:11434"
            CONFIG_VALUES[N8N_URL]="http://localhost:5678"
            break
        elif is_valid_domain "$domain" || is_valid_ip "$domain"; then
            CONFIG_VALUES[BASE_DOMAIN]="$domain"
            
            # Ask for subdomains
            local webui_subdomain=$(prompt_with_default "Open WebUI subdomain" "chat")
            local n8n_subdomain=$(prompt_with_default "n8n subdomain" "n8n")
            local ollama_subdomain=$(prompt_with_default "Ollama subdomain" "api")
            
            CONFIG_VALUES[WEBUI_URL]="https://${webui_subdomain}.${domain}"
            CONFIG_VALUES[OLLAMA_URL]="https://${ollama_subdomain}.${domain}"
            CONFIG_VALUES[N8N_URL]="https://${n8n_subdomain}.${domain}"
            break
        else
            log_error "Invalid domain or IP address"
        fi
    done
    
    log_info "Domain configured: ${CONFIG_VALUES[BASE_DOMAIN]}"
}

#==============================================================================
# STEP 6: SERVICE PORTS CONFIGURATION
#==============================================================================

step_06_service_ports() {
    print_step_header 5 "Service Ports Configuration"
    
    cat << 'EOF'
Configure service ports (use defaults unless there are conflicts).

Default ports:
  • Ollama: 11434
  • Open WebUI: 3000
  • n8n: 5678
  • PostgreSQL: 5432
  • Redis: 6379
  • Nginx HTTP: 80
  • Nginx HTTPS: 443

EOF

    if [[ "${CONFIG_VALUES[PROXY_TYPE]}" == "none" ]]; then
        log_info "Configuring service ports for direct access..."
        
        if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
            while true; do
                local port=$(prompt_with_default "Ollama port" "11434")
                if is_valid_port "$port" && is_port_available "$port"; then
                    CONFIG_VALUES[OLLAMA_PORT]="$port"
                    break
                else
                    log_error "Port $port is invalid or already in use"
                fi
            done
        fi
        
        if [[ "${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}" == "true" ]]; then
            while true; do
                local port=$(prompt_with_default "Open WebUI port" "3000")
                if is_valid_port "$port" && is_port_available "$port"; then
                    CONFIG_VALUES[OPEN_WEBUI_PORT]="$port"
                    break
                else
                    log_error "Port $port is invalid or already in use"
                fi
            done
        fi
        
        if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
            while true; do
                local port=$(prompt_with_default "n8n port" "5678")
                if is_valid_port "$port" && is_port_available "$port"; then
                    CONFIG_VALUES[N8N_PORT]="$port"
                    break
                else
                    log_error "Port $port is invalid or already in use"
                fi
            done
        fi
        
        if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
            while true; do
                local port=$(prompt_with_default "PostgreSQL port" "5432")
                if is_valid_port "$port" && is_port_available "$port"; then
                    CONFIG_VALUES[POSTGRES_PORT]="$port"
                    break
                else
                    log_error "Port $port is invalid or already in use"
                fi
            done
        fi
        
        if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
            while true; do
                local port=$(prompt_with_default "Redis port" "6379")
                if is_valid_port "$port" && is_port_available "$port"; then
                    CONFIG_VALUES[REDIS_PORT]="$port"
                    break
                else
                    log_error "Port $port is invalid or already in use"
                fi
            done
        fi
    else
        log_info "Using default internal ports (proxied via ${CONFIG_VALUES[PROXY_TYPE]})"
    fi
    
    # Port health checks
    cat << 'EOF'

Port Health Check Configuration:
  Configure health check intervals and timeouts for each service.

EOF
    
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        CONFIG_VALUES[OLLAMA_HEALTH_INTERVAL]=$(prompt_with_default "Ollama health check interval (seconds)" "30")
        CONFIG_VALUES[OLLAMA_HEALTH_TIMEOUT]=$(prompt_with_default "Ollama health check timeout (seconds)" "10")
        CONFIG_VALUES[OLLAMA_HEALTH_RETRIES]=$(prompt_with_default "Ollama health check retries" "3")
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}" == "true" ]]; then
        CONFIG_VALUES[WEBUI_HEALTH_INTERVAL]=$(prompt_with_default "WebUI health check interval (seconds)" "30")
        CONFIG_VALUES[WEBUI_HEALTH_TIMEOUT]=$(prompt_with_default "WebUI health check timeout (seconds)" "5")
        CONFIG_VALUES[WEBUI_HEALTH_RETRIES]=$(prompt_with_default "WebUI health check retries" "3")
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        CONFIG_VALUES[N8N_HEALTH_INTERVAL]=$(prompt_with_default "n8n health check interval (seconds)" "30")
        CONFIG_VALUES[N8N_HEALTH_TIMEOUT]=$(prompt_with_default "n8n health check timeout (seconds)" "5")
        CONFIG_VALUES[N8N_HEALTH_RETRIES]=$(prompt_with_default "n8n health check retries" "3")
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
        CONFIG_VALUES[POSTGRES_HEALTH_INTERVAL]=$(prompt_with_default "PostgreSQL health check interval (seconds)" "10")
        CONFIG_VALUES[POSTGRES_HEALTH_TIMEOUT]=$(prompt_with_default "PostgreSQL health check timeout (seconds)" "5")
        CONFIG_VALUES[POSTGRES_HEALTH_RETRIES]=$(prompt_with_default "PostgreSQL health check retries" "5")
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
        CONFIG_VALUES[REDIS_HEALTH_INTERVAL]=$(prompt_with_default "Redis health check interval (seconds)" "10")
        CONFIG_VALUES[REDIS_HEALTH_TIMEOUT]=$(prompt_with_default "Redis health check timeout (seconds)" "3")
        CONFIG_VALUES[REDIS_HEALTH_RETRIES]=$(prompt_with_default "Redis health check retries" "5")
    fi
    
    log_success "Ports and health checks configured"
}

#==============================================================================
# STEP 7: LLM PROVIDER CONFIGURATION
#==============================================================================

step_07_llm_providers() {
    print_step_header 6 "LLM Provider Configuration"
    
    cat << 'EOF'
Configure LLM providers for your platform.

Options:
  1) Local Only     - Use only local Ollama models
  2) External Only  - Use only cloud APIs (OpenAI, Anthropic, etc.)
  3) Hybrid         - Both local and external (via LiteLLM)
  4) LiteLLM Proxy  - Unified API for multiple providers

EOF

    local provider_mode=$(prompt_choice "LLM provider mode:" "Local Only" "External Only" "Hybrid" "LiteLLM Proxy")
    CONFIG_VALUES[LLM_PROVIDER_MODE]="$provider_mode"
    
    case "$provider_mode" in
        "Local Only")
            if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" != "true" ]]; then
                log_error "Ollama must be installed for local-only mode"
                CONFIG_VALUES[INSTALL_OLLAMA]="true"
                log_info "Enabling Ollama installation"
            fi
            ;;
            
        "External Only"|"Hybrid"|"LiteLLM Proxy")
            CONFIG_VALUES[INSTALL_LITELLM]="true"
            
            cat << 'EOF'

Configure external LLM providers:

Available providers:
  • OpenAI (GPT-4, GPT-3.5)
  • Anthropic (Claude)
  • Google (PaLM, Gemini)
  • Cohere
  • Azure OpenAI
  • AWS Bedrock

EOF
            
            # OpenAI
            if prompt_yes_no "Configure OpenAI?" "n"; then
                CONFIG_VALUES[OPENAI_ENABLED]="true"
                CONFIG_VALUES[OPENAI_API_KEY]=$(prompt_required "OpenAI API Key")
                CONFIG_VALUES[OPENAI_ORG_ID]=$(prompt_with_default "OpenAI Organization ID (optional)" "")
            fi
            
            # Anthropic
            if prompt_yes_no "Configure Anthropic (Claude)?" "n"; then
                CONFIG_VALUES[ANTHROPIC_ENABLED]="true"
                CONFIG_VALUES[ANTHROPIC_API_KEY]=$(prompt_required "Anthropic API Key")
            fi
            
            # Google
            if prompt_yes_no "Configure Google AI?" "n"; then
                CONFIG_VALUES[GOOGLE_ENABLED]="true"
                CONFIG_VALUES[GOOGLE_API_KEY]=$(prompt_required "Google AI API Key")
            fi
            
            # Azure OpenAI
            if prompt_yes_no "Configure Azure OpenAI?" "n"; then
                CONFIG_VALUES[AZURE_ENABLED]="true"
                CONFIG_VALUES[AZURE_API_KEY]=$(prompt_required "Azure OpenAI API Key")
                CONFIG_VALUES[AZURE_ENDPOINT]=$(prompt_required "Azure OpenAI Endpoint")
                CONFIG_VALUES[AZURE_DEPLOYMENT_NAME]=$(prompt_required "Azure Deployment Name")
            fi
            
            # AWS Bedrock
            if prompt_yes_no "Configure AWS Bedrock?" "n"; then
                CONFIG_VALUES[AWS_BEDROCK_ENABLED]="true"
                CONFIG_VALUES[AWS_ACCESS_KEY_ID]=$(prompt_required "AWS Access Key ID")
                CONFIG_VALUES[AWS_SECRET_ACCESS_KEY]=$(prompt_required "AWS Secret Access Key")
                CONFIG_VALUES[AWS_REGION]=$(prompt_with_default "AWS Region" "us-east-1")
            fi
            ;;
    esac
    
    log_success "LLM providers configured"
}

#==============================================================================
# STEP 8: VECTOR DATABASE SELECTION
#==============================================================================

step_08_vector_database() {
    print_step_header 7 "Vector Database Selection"
    
    cat << 'EOF'
Select a vector database for embeddings and semantic search:

  1) Qdrant     - Fast, Rust-based, feature-rich
  2) Chroma     - Simple, Python-based, lightweight
  3) Weaviate   - GraphQL API, hybrid search
  4) None       - No vector database

EOF

    local vector_db=$(prompt_choice "Vector database:" "Qdrant" "Chroma" "Weaviate" "None")
    
    case "$vector_db" in
        "Qdrant")
            CONFIG_VALUES[INSTALL_QDRANT]="true"
            CONFIG_VALUES[VECTOR_DB]="qdrant"
            CONFIG_VALUES[QDRANT_PORT]=$(prompt_with_default "Qdrant port" "6333")
            ;;
        "Chroma")
            CONFIG_VALUES[INSTALL_CHROMA]="true"
            CONFIG_VALUES[VECTOR_DB]="chroma"
            CONFIG_VALUES[CHROMA_PORT]=$(prompt_with_default "Chroma port" "8000")
            ;;
        "Weaviate")
            CONFIG_VALUES[INSTALL_WEAVIATE]="true"
            CONFIG_VALUES[VECTOR_DB]="weaviate"
            CONFIG_VALUES[WEAVIATE_PORT]=$(prompt_with_default "Weaviate port" "8080")
            ;;
        "None")
            CONFIG_VALUES[VECTOR_DB]="none"
            log_info "No vector database selected"
            ;;
    esac
}

#==============================================================================
# STEP 9: AUTHENTICATION CONFIGURATION
#==============================================================================

step_09_authentication() {
    print_step_header 8 "Authentication Configuration"
    
    cat << 'EOF'
Configure authentication for platform access:

  1) Local      - Username/password (stored in database)
  2) LDAP/AD    - Corporate directory integration
  3) OAuth2     - Google, GitHub, Azure AD, etc.
  4) SAML       - Enterprise SSO
  5) Multiple   - Combine multiple auth methods

EOF

    local auth_method=$(prompt_choice "Authentication method:" "Local" "LDAP/AD" "OAuth2" "SAML" "Multiple")
    CONFIG_VALUES[AUTH_METHOD]="$auth_method"
    
    case "$auth_method" in
        "Local")
            CONFIG_VALUES[AUTH_TYPE]="local"
            CONFIG_VALUES[ADMIN_USERNAME]=$(prompt_with_default "Admin username" "admin")
            CONFIG_VALUES[ADMIN_PASSWORD]=$(generate_password 16)
            CONFIG_VALUES[ADMIN_EMAIL]=$(prompt_required "Admin email")
            log_info "Admin password generated: ${CONFIG_VALUES[ADMIN_PASSWORD]}"
            ;;
            
        "LDAP/AD")
            CONFIG_VALUES[AUTH_TYPE]="ldap"
            CONFIG_VALUES[LDAP_URL]=$(prompt_required "LDAP Server URL (e.g., ldap://ldap.example.com)")
            CONFIG_VALUES[LDAP_BIND_DN]=$(prompt_required "LDAP Bind DN")
            CONFIG_VALUES[LDAP_BIND_PASSWORD]=$(prompt_required "LDAP Bind Password")
            CONFIG_VALUES[LDAP_SEARCH_BASE]=$(prompt_required "LDAP Search Base (e.g., ou=users,dc=example,dc=com)")
            CONFIG_VALUES[LDAP_USER_FILTER]=$(prompt_with_default "LDAP User Filter" "(uid=%s)")
            ;;
            
        "OAuth2")
            CONFIG_VALUES[AUTH_TYPE]="oauth2"
            
            if prompt_yes_no "Configure Google OAuth?" "n"; then
                CONFIG_VALUES[OAUTH_GOOGLE_ENABLED]="true"
                CONFIG_VALUES[OAUTH_GOOGLE_CLIENT_ID]=$(prompt_required "Google OAuth Client ID")
                CONFIG_VALUES[OAUTH_GOOGLE_CLIENT_SECRET]=$(prompt_required "Google OAuth Client Secret")
            fi
            
            if prompt_yes_no "Configure GitHub OAuth?" "n"; then
                CONFIG_VALUES[OAUTH_GITHUB_ENABLED]="true"
                CONFIG_VALUES[OAUTH_GITHUB_CLIENT_ID]=$(prompt_required "GitHub OAuth Client ID")
                CONFIG_VALUES[OAUTH_GITHUB_CLIENT_SECRET]=$(prompt_required "GitHub OAuth Client Secret")
            fi
            
            if prompt_yes_no "Configure Azure AD OAuth?" "n"; then
                CONFIG_VALUES[OAUTH_AZURE_ENABLED]="true"
                CONFIG_VALUES[OAUTH_AZURE_CLIENT_ID]=$(prompt_required "Azure AD Client ID")
                CONFIG_VALUES[OAUTH_AZURE_CLIENT_SECRET]=$(prompt_required "Azure AD Client Secret")
                CONFIG_VALUES[OAUTH_AZURE_TENANT_ID]=$(prompt_required "Azure AD Tenant ID")
            fi
            ;;
            
        "SAML")
            CONFIG_VALUES[AUTH_TYPE]="saml"
            CONFIG_VALUES[SAML_ENTITY_ID]=$(prompt_required "SAML Entity ID")
            CONFIG_VALUES[SAML_SSO_URL]=$(prompt_required "SAML SSO URL")
            CONFIG_VALUES[SAML_CERT_PATH]=$(prompt_required "SAML Certificate Path")
            ;;
            
        "Multiple")
            CONFIG_VALUES[AUTH_TYPE]="multiple"
            log_info "Multiple auth methods - combine configurations above"
            ;;
    esac
    
    log_success "Authentication configured"
}

#==============================================================================
# STEP 10: MONITORING STACK (OPTIONAL)
#==============================================================================

step_10_monitoring() {
    print_step_header 9 "Monitoring Stack (Optional)"
    
    cat << 'EOF'
Optional monitoring and observability stack:

Components:
  • Prometheus  - Metrics collection and storage
  • Grafana     - Metrics visualization and dashboards
  • Loki        - Log aggregation
  • Tempo       - Distributed tracing
  • Alertmanager- Alert routing and management

EOF

    if prompt_yes_no "Install monitoring stack?" "n"; then
        CONFIG_VALUES[INSTALL_MONITORING]="true"
        
        # Prometheus
        if prompt_yes_no "Install Prometheus?" "y"; then
            CONFIG_VALUES[INSTALL_PROMETHEUS]="true"
            CONFIG_VALUES[PROMETHEUS_PORT]=$(prompt_with_default "Prometheus port" "9090")
            CONFIG_VALUES[PROMETHEUS_RETENTION]=$(prompt_with_default "Metrics retention (days)" "15")
        fi
        
        # Grafana
        if prompt_yes_no "Install Grafana?" "y"; then
            CONFIG_VALUES[INSTALL_GRAFANA]="true"
            CONFIG_VALUES[GRAFANA_PORT]=$(prompt_with_default "Grafana port" "3001")
            CONFIG_VALUES[GRAFANA_ADMIN_PASSWORD]=$(generate_password 16)
            log_info "Grafana admin password: ${CONFIG_VALUES[GRAFANA_ADMIN_PASSWORD]}"
        fi
        
        # Loki
        if prompt_yes_no "Install Loki (logs)?" "n"; then
            CONFIG_VALUES[INSTALL_LOKI]="true"
            CONFIG_VALUES[LOKI_PORT]=$(prompt_with_default "Loki port" "3100")
        fi
        
        # Tempo
        if prompt_yes_no "Install Tempo (tracing)?" "n"; then
            CONFIG_VALUES[INSTALL_TEMPO]="true"
            CONFIG_VALUES[TEMPO_PORT]=$(prompt_with_default "Tempo port" "3200")
        fi
        
        # Alertmanager
        if prompt_yes_no "Install Alertmanager?" "n"; then
            CONFIG_VALUES[INSTALL_ALERTMANAGER]="true"
            CONFIG_VALUES[ALERTMANAGER_PORT]=$(prompt_with_default "Alertmanager port" "9093")
        fi
    else
        CONFIG_VALUES[INSTALL_MONITORING]="false"
        log_info "Monitoring stack disabled"
    fi
}

#==============================================================================
# STEP 11: DATABASE CONFIGURATION
#==============================================================================

step_11_database() {
    print_step_header 10 "Database Configuration"
    
    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
        cat << 'EOF'
Configure PostgreSQL database:

EOF
        CONFIG_VALUES[POSTGRES_DB]=$(prompt_with_default "Database name" "aiplatform")
        CONFIG_VALUES[POSTGRES_USER]=$(prompt_with_default "Database user" "aiplatform")
        CONFIG_VALUES[POSTGRES_PASSWORD]=$(generate_password 32)
        
        log_info "PostgreSQL credentials:"
        log_info "  Database: ${CONFIG_VALUES[POSTGRES_DB]}"
        log_info "  User: ${CONFIG_VALUES[POSTGRES_USER]}"
        log_info "  Password: ${CONFIG_VALUES[POSTGRES_PASSWORD]}"
        
        # Backup configuration
        if prompt_yes_no "Enable automated PostgreSQL backups?" "y"; then
            CONFIG_VALUES[POSTGRES_BACKUP_ENABLED]="true"
            CONFIG_VALUES[POSTGRES_BACKUP_SCHEDULE]=$(prompt_with_default "Backup schedule (cron)" "0 2 * * *")
            CONFIG_VALUES[POSTGRES_BACKUP_RETENTION]=$(prompt_with_default "Backup retention (days)" "7")
        fi
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
        cat << 'EOF'

Configure Redis cache:

EOF
        CONFIG_VALUES[REDIS_PASSWORD]=$(generate_password 32)
        CONFIG_VALUES[REDIS_MAX_MEMORY]=$(prompt_with_default "Max memory (e.g., 512mb, 2gb)" "512mb")
        CONFIG_VALUES[REDIS_EVICTION_POLICY]=$(prompt_with_default "Eviction policy" "allkeys-lru")
        
        log_info "Redis password: ${CONFIG_VALUES[REDIS_PASSWORD]}"
    fi
    
    log_success "Database configuration complete"
}

#==============================================================================
# STEP 12: RESOURCE LIMITS
#==============================================================================

step_12_resources() {
    print_step_header 11 "Resource Limits"
    
    cat << 'EOF'
Configure resource limits for services.

Recommendations:
  • Ollama: 8GB RAM, 4 CPUs (more if using large models)
  • Open WebUI: 2GB RAM, 2 CPUs
  • n8n: 2GB RAM, 2 CPUs
  • PostgreSQL: 2GB RAM, 2 CPUs
  • Redis: 512MB RAM, 1 CPU

EOF

    # Detect available resources
    local total_memory=$(free -g | awk '/^Mem:/ {print $2}')
    local total_cpus=$(nproc)
    
    log_info "System resources: ${total_memory}GB RAM, ${total_cpus} CPUs"
    
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        CONFIG_VALUES[OLLAMA_MAX_MEMORY]=$(prompt_with_default "Ollama max memory" "8g")
        CONFIG_VALUES[OLLAMA_MAX_CPUS]=$(prompt_with_default "Ollama max CPUs" "4")
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}" == "true" ]]; then
        CONFIG_VALUES[WEBUI_MAX_MEMORY]=$(prompt_with_default "WebUI max memory" "2g")
        CONFIG_VALUES[WEBUI_MAX_CPUS]=$(prompt_with_default "WebUI max CPUs" "2")
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        CONFIG_VALUES[N8N_MAX_MEMORY]=$(prompt_with_default "n8n max memory" "2g")
        CONFIG_VALUES[N8N_MAX_CPUS]=$(prompt_with_default "n8n max CPUs" "2")
    fi
    
    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
        CONFIG_VALUES[POSTGRES_MAX_MEMORY]=$(prompt_with_default "PostgreSQL max memory" "2g")
        CONFIG_VALUES[POSTGRES_MAX_CPUS]=$(prompt_with_default "PostgreSQL max CPUs" "2")
    fi
    
    log_success "Resource limits configured"
}

#==============================================================================
# STEP 13: GPU CONFIGURATION
#==============================================================================

step_13_gpu() {
    print_step_header 12 "GPU Configuration"
    
    cat << 'EOF'
GPU acceleration for LLM inference:

EOF

    # Detect GPU
    local gpu_detected="none"
    if detect_nvidia_gpu; then
        gpu_detected="nvidia"
        log_success "NVIDIA GPU detected"
    elif detect_amd_gpu; then
        gpu_detected="amd"
        log_success "AMD GPU detected"
    else
        log_info "No GPU detected"
    fi
    
    if [[ "$gpu_detected" != "none" ]]; then
        if prompt_yes_no "Enable GPU acceleration?" "y"; then
            CONFIG_VALUES[ENABLE_GPU]="true"
            CONFIG_VALUES[GPU_TYPE]="$gpu_detected"
            
            if [[ "$gpu_detected" == "nvidia" ]]; then
                log_info "Installing NVIDIA Container Toolkit..."
                install_nvidia_docker
            fi
        else
            CONFIG_VALUES[ENABLE_GPU]="false"
        fi
    else
        CONFIG_VALUES[ENABLE_GPU]="false"
        CONFIG_VALUES[GPU_TYPE]="none"
    fi
}

#==============================================================================
# STEP 14: SSL/TLS CONFIGURATION
#==============================================================================

step_14_ssl() {
    print_step_header 13 "SSL/TLS Configuration"
    
    if [[ "${CONFIG_VALUES[BASE_DOMAIN]}" == "localhost" ]]; then
        log_info "Localhost deployment - SSL not required"
        CONFIG_VALUES[ENABLE_SSL]="false"
        return 0
    fi
    
    cat << 'EOF'
Configure SSL/TLS certificates:

  1) Let's Encrypt  - Free automated certificates
  2) Self-signed    - For testing/development
  3) Custom         - Provide your own certificates
  4) None           - HTTP only (not recommended)

EOF

    local ssl_option=$(prompt_choice "SSL configuration:" "Let's Encrypt" "Self-signed" "Custom" "None")
    
    case "$ssl_option" in
        "Let's Encrypt")
            CONFIG_VALUES[ENABLE_SSL]="true"
            CONFIG_VALUES[SSL_TYPE]="letsencrypt"
            CONFIG_VALUES[SSL_EMAIL]=$(prompt_required "Email for SSL notifications")
            ;;
        "Self-signed")
            CONFIG_VALUES[ENABLE_SSL]="true"
            CONFIG_VALUES[SSL_TYPE]="selfsigned"
            ;;
        "Custom")
            CONFIG_VALUES[ENABLE_SSL]="true"
            CONFIG_VALUES[SSL_TYPE]="custom"
            CONFIG_VALUES[SSL_CERT_PATH]=$(prompt_required "SSL certificate path")
            CONFIG_VALUES[SSL_KEY_PATH]=$(prompt_required "SSL private key path")
            ;;
        "None")
            CONFIG_VALUES[ENABLE_SSL]="false"
            log_warning "SSL disabled - traffic will be unencrypted"
            ;;
    esac
    
    log_success "SSL configuration complete"
}

#==============================================================================
# END OF PART 2/4
#==============================================================================
#!/bin/bash
################################################################################
# AI Platform Automation - System Setup Script  
# Part 3/4: Configuration Wizard Steps 15-27 + File Generation (CORRECTED)
################################################################################

#==============================================================================
# STEP 15: BACKUP & DISASTER RECOVERY
#==============================================================================

step_15_backup() {
    print_step_header 14 "Backup & Disaster Recovery"
    
    cat << 'EOF'
Configure automated backups for data protection:

Backup targets:
  • Docker volumes (all persistent data)
  • Configuration files (.env, docker-compose.yml)
  • Databases (PostgreSQL dumps)
  • Models (Ollama model files)

EOF

    if prompt_yes_no "Enable automated backups?" "y"; then
        CONFIG_VALUES[ENABLE_BACKUPS]="true"
        
        # Backup schedule
        CONFIG_VALUES[BACKUP_SCHEDULE]=$(prompt_with_default "Backup schedule (cron format)" "0 3 * * *")
        
        # Backup retention
        CONFIG_VALUES[BACKUP_RETENTION_DAYS]=$(prompt_with_default "Backup retention (days)" "7")
        
        # Backup location
        cat << 'EOF'

Backup storage options:
  1) Local      - Store on same server
  2) S3         - AWS S3 or compatible
  3) FTP/SFTP   - Remote FTP server
  4) NFS        - Network file system
  5) Multiple   - Combine locations

EOF
        
        local backup_location=$(prompt_choice "Backup storage:" "Local" "S3" "FTP/SFTP" "NFS" "Multiple")
        CONFIG_VALUES[BACKUP_STORAGE]="$backup_location"
        
        case "$backup_location" in
            "S3")
                CONFIG_VALUES[S3_BACKUP_ENABLED]="true"
                CONFIG_VALUES[S3_BUCKET]=$(prompt_required "S3 bucket name")
                CONFIG_VALUES[S3_REGION]=$(prompt_with_default "S3 region" "us-east-1")
                CONFIG_VALUES[S3_ACCESS_KEY]=$(prompt_required "S3 access key")
                CONFIG_VALUES[S3_SECRET_KEY]=$(prompt_required "S3 secret key")
                ;;
            "FTP/SFTP")
                CONFIG_VALUES[FTP_BACKUP_ENABLED]="true"
                CONFIG_VALUES[FTP_HOST]=$(prompt_required "FTP/SFTP host")
                CONFIG_VALUES[FTP_PORT]=$(prompt_with_default "FTP/SFTP port" "22")
                CONFIG_VALUES[FTP_USER]=$(prompt_required "FTP/SFTP username")
                CONFIG_VALUES[FTP_PASSWORD]=$(prompt_required "FTP/SFTP password")
                CONFIG_VALUES[FTP_PATH]=$(prompt_with_default "Remote path" "/backups")
                ;;
            "NFS")
                CONFIG_VALUES[NFS_BACKUP_ENABLED]="true"
                CONFIG_VALUES[NFS_SERVER]=$(prompt_required "NFS server address")
                CONFIG_VALUES[NFS_PATH]=$(prompt_required "NFS export path")
                ;;
        esac
        
        # Compression
        if prompt_yes_no "Enable backup compression?" "y"; then
            CONFIG_VALUES[BACKUP_COMPRESSION]="true"
            CONFIG_VALUES[BACKUP_COMPRESSION_LEVEL]=$(prompt_with_default "Compression level (1-9)" "6")
        fi
        
        # Encryption
        if prompt_yes_no "Encrypt backups?" "y"; then
            CONFIG_VALUES[BACKUP_ENCRYPTION]="true"
            CONFIG_VALUES[BACKUP_ENCRYPTION_KEY]=$(generate_secret 32)
            log_info "Backup encryption key: ${CONFIG_VALUES[BACKUP_ENCRYPTION_KEY]}"
        fi
        
    else
        CONFIG_VALUES[ENABLE_BACKUPS]="false"
        log_warning "Backups disabled - manual backup recommended"
    fi
    
    log_success "Backup configuration complete"
}

#==============================================================================
# STEP 16: LOGGING & OBSERVABILITY
#==============================================================================

step_16_logging() {
    print_step_header 15 "Logging & Observability"
    
    cat << 'EOF'
Configure centralized logging and log management:

EOF

    # Log level
    cat << 'EOF'
Select log verbosity:
  1) ERROR   - Only errors
  2) WARN    - Warnings and errors
  3) INFO    - General information (recommended)
  4) DEBUG   - Detailed debugging
  5) TRACE   - Everything (very verbose)

EOF
    
    local log_level=$(prompt_choice "Log level:" "ERROR" "WARN" "INFO" "DEBUG" "TRACE")
    CONFIG_VALUES[LOG_LEVEL]="$log_level"
    
    # Log retention
    CONFIG_VALUES[LOG_RETENTION_DAYS]=$(prompt_with_default "Log retention (days)" "30")
    
    # Structured logging
    if prompt_yes_no "Enable structured JSON logging?" "y"; then
        CONFIG_VALUES[STRUCTURED_LOGGING]="true"
    else
        CONFIG_VALUES[STRUCTURED_LOGGING]="false"
    fi
    
    # External log shipping
    if prompt_yes_no "Ship logs to external service?" "n"; then
        cat << 'EOF'

Log shipping destinations:
  1) Elasticsearch  - ELK stack
  2) Splunk        - Enterprise log management
  3) Datadog       - Cloud monitoring
  4) Syslog        - Standard syslog server
  5) Loki          - Grafana Loki

EOF
        
        local log_destination=$(prompt_choice "Log destination:" "Elasticsearch" "Splunk" "Datadog" "Syslog" "Loki")
        CONFIG_VALUES[LOG_SHIPPING_ENABLED]="true"
        CONFIG_VALUES[LOG_DESTINATION]="$log_destination"
        
        case "$log_destination" in
            "Elasticsearch")
                CONFIG_VALUES[ELASTICSEARCH_URL]=$(prompt_required "Elasticsearch URL")
                CONFIG_VALUES[ELASTICSEARCH_INDEX]=$(prompt_with_default "Index name" "aiplatform-logs")
                ;;
            "Splunk")
                CONFIG_VALUES[SPLUNK_URL]=$(prompt_required "Splunk HEC URL")
                CONFIG_VALUES[SPLUNK_TOKEN]=$(prompt_required "Splunk HEC token")
                ;;
            "Datadog")
                CONFIG_VALUES[DATADOG_API_KEY]=$(prompt_required "Datadog API key")
                CONFIG_VALUES[DATADOG_SITE]=$(prompt_with_default "Datadog site" "datadoghq.com")
                ;;
            "Syslog")
                CONFIG_VALUES[SYSLOG_HOST]=$(prompt_required "Syslog server")
                CONFIG_VALUES[SYSLOG_PORT]=$(prompt_with_default "Syslog port" "514")
                ;;
        esac
    fi
    
    log_success "Logging configuration complete"
}

#==============================================================================
# STEP 17: SECURITY HARDENING
#==============================================================================

step_17_security() {
    print_step_header 16 "Security Hardening"
    
    cat << 'EOF'
Configure security policies and hardening options:

EOF

    # Firewall
    if prompt_yes_no "Configure firewall rules?" "y"; then
        CONFIG_VALUES[ENABLE_FIREWALL]="true"
        
        if prompt_yes_no "Allow SSH access?" "y"; then
            CONFIG_VALUES[FIREWALL_ALLOW_SSH]="true"
            CONFIG_VALUES[SSH_PORT]=$(prompt_with_default "SSH port" "22")
        fi
        
        if prompt_yes_no "Restrict access to specific IPs?" "n"; then
            CONFIG_VALUES[FIREWALL_WHITELIST_ENABLED]="true"
            CONFIG_VALUES[FIREWALL_WHITELIST_IPS]=$(prompt_required "Allowed IPs (comma-separated)")
        fi
    fi
    
    # Rate limiting
    if prompt_yes_no "Enable API rate limiting?" "y"; then
        CONFIG_VALUES[RATE_LIMITING_ENABLED]="true"
        CONFIG_VALUES[RATE_LIMIT_REQUESTS]=$(prompt_with_default "Requests per minute" "60")
        CONFIG_VALUES[RATE_LIMIT_BURST]=$(prompt_with_default "Burst size" "10")
    fi
    
    # CORS
    if prompt_yes_no "Configure CORS (Cross-Origin Resource Sharing)?" "y"; then
        CONFIG_VALUES[CORS_ENABLED]="true"
        CONFIG_VALUES[CORS_ALLOWED_ORIGINS]=$(prompt_with_default "Allowed origins (* for all)" "${CONFIG_VALUES[BASE_DOMAIN]}")
    fi
    
    # Security headers
    if prompt_yes_no "Enable security headers (HSTS, CSP, etc.)?" "y"; then
        CONFIG_VALUES[SECURITY_HEADERS_ENABLED]="true"
    fi
    
    # Fail2ban
    if prompt_yes_no "Install Fail2ban (brute-force protection)?" "y"; then
        CONFIG_VALUES[INSTALL_FAIL2BAN]="true"
        CONFIG_VALUES[FAIL2BAN_MAXRETRY]=$(prompt_with_default "Max login attempts" "5")
        CONFIG_VALUES[FAIL2BAN_BANTIME]=$(prompt_with_default "Ban duration (seconds)" "3600")
    fi
    
    # Content Security Policy
    if prompt_yes_no "Enable strict Content Security Policy?" "n"; then
        CONFIG_VALUES[CSP_ENABLED]="true"
    fi
    
    log_success "Security hardening configured"
}

#==============================================================================
# STEP 18: MODEL MANAGEMENT
#==============================================================================

step_18_models() {
    print_step_header 17 "Model Management"
    
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" != "true" ]]; then
        log_info "Ollama not installed - skipping model configuration"
        return 0
    fi
    
    cat << 'EOF'
Configure which LLM models to download on first start:

Popular models:
  • llama3.2:latest      (3B params, fast, general purpose)
  • llama3.2:70b         (70B params, powerful, slow)
  • mistral:latest       (7B params, balanced)
  • codellama:latest     (7B params, code-focused)
  • llama3-groq-tool-use (8B params, function calling)

You can add more models later using: ollama pull <model>

EOF

    if prompt_yes_no "Pre-download models on deployment?" "y"; then
        CONFIG_VALUES[PRELOAD_MODELS]="true"
        
        # Model selection
        local models=""
        
        if prompt_yes_no "Install llama3.2 (3B, recommended)?" "y"; then
            models="${models},llama3.2:latest"
        fi
        
        if prompt_yes_no "Install mistral (7B)?" "n"; then
            models="${models},mistral:latest"
        fi
        
        if prompt_yes_no "Install codellama (7B, code)?" "n"; then
            models="${models},codellama:latest"
        fi
        
        if prompt_yes_no "Install llama3.2:70b (70B, powerful)?" "n"; then
            models="${models},llama3.2:70b"
        fi
        
        # Custom models
        if prompt_yes_no "Add custom models?" "n"; then
            local custom_models=$(prompt_required "Custom models (comma-separated)")
            models="${models},${custom_models}"
        fi
        
        # Remove leading comma
        models="${models#,}"
        CONFIG_VALUES[OLLAMA_MODELS]="$models"
        
        log_info "Models to download: $models"
    else
        CONFIG_VALUES[PRELOAD_MODELS]="false"
    fi
    
    # Model storage path
    CONFIG_VALUES[OLLAMA_MODELS_DIR]=$(prompt_with_default "Model storage directory" "${DATA_DIR}/ollama/models")
    
    log_success "Model management configured"
}

#==============================================================================
# STEP 19: NETWORK CONFIGURATION
#==============================================================================

step_19_network() {
    print_step_header 18 "Network Configuration"
    
    cat << 'EOF'
Configure Docker networking:

EOF

    # Docker network
    CONFIG_VALUES[DOCKER_NETWORK_NAME]=$(prompt_with_default "Docker network name" "aiplatform")
    CONFIG_VALUES[DOCKER_SUBNET]=$(prompt_with_default "Docker subnet" "172.28.0.0/16")
    CONFIG_VALUES[DOCKER_GATEWAY]=$(prompt_with_default "Docker gateway" "172.28.0.1")
    
    # IPv6
    if prompt_yes_no "Enable IPv6?" "n"; then
        CONFIG_VALUES[ENABLE_IPV6]="true"
        CONFIG_VALUES[DOCKER_SUBNET_IPV6]=$(prompt_with_default "IPv6 subnet" "fd00::/64")
    fi
    
    # DNS
    if prompt_yes_no "Configure custom DNS servers?" "n"; then
        CONFIG_VALUES[CUSTOM_DNS_ENABLED]="true"
        CONFIG_VALUES[DNS_SERVERS]=$(prompt_with_default "DNS servers (comma-separated)" "8.8.8.8,8.8.4.4")
    fi
    
    # MTU
    if prompt_yes_no "Configure custom MTU?" "n"; then
        CONFIG_VALUES[DOCKER_MTU]=$(prompt_with_default "MTU size" "1500")
    fi
    
    log_success "Network configuration complete"
}

#==============================================================================
# STEP 20: PERFORMANCE TUNING
#==============================================================================

step_20_performance() {
    print_step_header 19 "Performance Tuning"
    
    cat << 'EOF'
Configure performance optimizations:

EOF

    # Worker processes
    if [[ "${CONFIG_VALUES[INSTALL_NGINX]}" == "true" ]] || [[ "${CONFIG_VALUES[INSTALL_TRAEFIK]}" == "true" ]]; then
        local cpu_count=$(nproc)
        CONFIG_VALUES[PROXY_WORKER_PROCESSES]=$(prompt_with_default "Proxy worker processes" "$cpu_count")
        CONFIG_VALUES[PROXY_WORKER_CONNECTIONS]=$(prompt_with_default "Worker connections" "1024")
    fi
    
    # Connection pooling
    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
        CONFIG_VALUES[POSTGRES_MAX_CONNECTIONS]=$(prompt_with_default "PostgreSQL max connections" "100")
        CONFIG_VALUES[POSTGRES_SHARED_BUFFERS]=$(prompt_with_default "PostgreSQL shared buffers" "256MB")
    fi
    
    # Cache settings
    if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
        CONFIG_VALUES[REDIS_MAXMEMORY_POLICY]=$(prompt_with_default "Redis eviction policy" "allkeys-lru")
    fi
    
    # Model concurrency
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        CONFIG_VALUES[OLLAMA_NUM_PARALLEL]=$(prompt_with_default "Ollama parallel requests" "1")
        CONFIG_VALUES[OLLAMA_MAX_LOADED_MODELS]=$(prompt_with_default "Max loaded models" "1")
    fi
    
    # Keep-alive
    CONFIG_VALUES[KEEPALIVE_TIMEOUT]=$(prompt_with_default "Keep-alive timeout (seconds)" "65")
    
    log_success "Performance tuning complete"
}

#==============================================================================
# STEP 21: MAINTENANCE & UPDATES
#==============================================================================

step_21_maintenance() {
    print_step_header 20 "Maintenance & Updates"
    
    cat << 'EOF'
Configure automated maintenance tasks:

EOF

    # Watchtower (auto-updates)
    if prompt_yes_no "Enable Watchtower (auto-update containers)?" "n"; then
        CONFIG_VALUES[INSTALL_WATCHTOWER]="true"
        CONFIG_VALUES[WATCHTOWER_SCHEDULE]=$(prompt_with_default "Update check schedule (cron)" "0 4 * * 0")
        
        if prompt_yes_no "Enable automatic container updates?" "n"; then
            CONFIG_VALUES[WATCHTOWER_AUTO_UPDATE]="true"
        else
            CONFIG_VALUES[WATCHTOWER_AUTO_UPDATE]="false"
            CONFIG_VALUES[WATCHTOWER_NOTIFICATIONS_ONLY]="true"
        fi
    fi
    
    # Log rotation
    CONFIG_VALUES[LOG_ROTATION_ENABLED]="true"
    CONFIG_VALUES[LOG_MAX_SIZE]=$(prompt_with_default "Max log file size" "100M")
    CONFIG_VALUES[LOG_MAX_FILES]=$(prompt_with_default "Max log files to keep" "10")
    
    # Docker cleanup
    if prompt_yes_no "Enable automatic Docker cleanup?" "y"; then
        CONFIG_VALUES[DOCKER_CLEANUP_ENABLED]="true"
        CONFIG_VALUES[DOCKER_CLEANUP_SCHEDULE]=$(prompt_with_default "Cleanup schedule (cron)" "0 2 * * 0")
    fi
    
    # Health checks
    CONFIG_VALUES[HEALTH_CHECK_ENABLED]="true"
    CONFIG_VALUES[HEALTH_CHECK_INTERVAL]=$(prompt_with_default "Health check interval (seconds)" "30")
    
    log_success "Maintenance configuration complete"
}

#==============================================================================
# STEP 22: NOTIFICATION CHANNELS
#==============================================================================

step_22_notifications() {
    print_step_header 21 "Notification Channels"
    
    cat << 'EOF'
Configure notification channels for alerts and updates:

EOF

    # Email notifications
    if prompt_yes_no "Configure email notifications?" "n"; then
        CONFIG_VALUES[EMAIL_NOTIFICATIONS_ENABLED]="true"
        CONFIG_VALUES[SMTP_HOST]=$(prompt_required "SMTP server")
        CONFIG_VALUES[SMTP_PORT]=$(prompt_with_default "SMTP port" "587")
        CONFIG_VALUES[SMTP_USER]=$(prompt_required "SMTP username")
        CONFIG_VALUES[SMTP_PASSWORD]=$(prompt_required "SMTP password")
        CONFIG_VALUES[SMTP_FROM]=$(prompt_required "From email address")
        CONFIG_VALUES[SMTP_TO]=$(prompt_required "Alert recipient email")
        
        if prompt_yes_no "Use TLS/SSL?" "y"; then
            CONFIG_VALUES[SMTP_TLS]="true"
        fi
    fi
    
    # Slack notifications
    if prompt_yes_no "Configure Slack notifications?" "n"; then
        CONFIG_VALUES[SLACK_NOTIFICATIONS_ENABLED]="true"
        CONFIG_VALUES[SLACK_WEBHOOK_URL]=$(prompt_required "Slack webhook URL")
        CONFIG_VALUES[SLACK_CHANNEL]=$(prompt_with_default "Slack channel" "#alerts")
    fi
    
    # Discord notifications
    if prompt_yes_no "Configure Discord notifications?" "n"; then
        CONFIG_VALUES[DISCORD_NOTIFICATIONS_ENABLED]="true"
        CONFIG_VALUES[DISCORD_WEBHOOK_URL]=$(prompt_required "Discord webhook URL")
    fi
    
    # Telegram notifications
    if prompt_yes_no "Configure Telegram notifications?" "n"; then
        CONFIG_VALUES[TELEGRAM_NOTIFICATIONS_ENABLED]="true"
        CONFIG_VALUES[TELEGRAM_BOT_TOKEN]=$(prompt_required "Telegram bot token")
        CONFIG_VALUES[TELEGRAM_CHAT_ID]=$(prompt_required "Telegram chat ID")
    fi
    
    # PagerDuty
    if prompt_yes_no "Configure PagerDuty?" "n"; then
        CONFIG_VALUES[PAGERDUTY_ENABLED]="true"
        CONFIG_VALUES[PAGERDUTY_KEY]=$(prompt_required "PagerDuty integration key")
    fi
    
    log_success "Notification channels configured"
}

#==============================================================================
# STEP 23: INTEGRATIONS & WEBHOOKS
#==============================================================================

step_23_integrations() {
    print_step_header 22 "Integrations & Webhooks"
    
    cat << 'EOF'
Configure external integrations and webhooks:

EOF

    # Webhook for events
    if prompt_yes_no "Configure event webhooks?" "n"; then
        CONFIG_VALUES[WEBHOOKS_ENABLED]="true"
        CONFIG_VALUES[WEBHOOK_URL]=$(prompt_required "Webhook URL")
        CONFIG_VALUES[WEBHOOK_SECRET]=$(generate_secret 32)
        log_info "Webhook secret: ${CONFIG_VALUES[WEBHOOK_SECRET]}"
    fi
    
    # GitHub integration
    if prompt_yes_no "Configure GitHub integration?" "n"; then
        CONFIG_VALUES[GITHUB_INTEGRATION_ENABLED]="true"
        CONFIG_VALUES[GITHUB_TOKEN]=$(prompt_required "GitHub personal access token")
        CONFIG_VALUES[GITHUB_ORG]=$(prompt_with_default "GitHub organization" "")
    fi
    
    # Jira integration
    if prompt_yes_no "Configure Jira integration?" "n"; then
        CONFIG_VALUES[JIRA_ENABLED]="true"
        CONFIG_VALUES[JIRA_URL]=$(prompt_required "Jira instance URL")
        CONFIG_VALUES[JIRA_USER]=$(prompt_required "Jira username")
        CONFIG_VALUES[JIRA_API_TOKEN]=$(prompt_required "Jira API token")
    fi
    
    log_success "Integrations configured"
}

#==============================================================================
# STEP 24: API KEYS & SECRETS
#==============================================================================

step_24_secrets() {
    print_step_header 23 "API Keys & Secrets Management"
    
    cat << 'EOF'
Generate secure secrets for internal services:

EOF

    # Generate JWT secrets
    CONFIG_VALUES[JWT_SECRET]=$(generate_jwt_secret)
    CONFIG_VALUES[SESSION_SECRET]=$(generate_secret 32)
    CONFIG_VALUES[ENCRYPTION_KEY]=$(generate_secret 32)
    
    log_info "Generated secure secrets (saved to .env file)"
    
    # API key for external access
    if prompt_yes_no "Generate API key for external access?" "y"; then
        CONFIG_VALUES[API_KEY]=$(generate_secret 32)
        CONFIG_VALUES[API_KEY_ENABLED]="true"
        log_info "API Key: ${CONFIG_VALUES[API_KEY]}"
    fi
    
    # Webhook signatures
    CONFIG_VALUES[WEBHOOK_SIGNING_SECRET]=$(generate_secret 32)
    
    log_success "Secrets generated and secured"
}

#==============================================================================
# STEP 25: CUSTOM ENVIRONMENT VARIABLES
#==============================================================================

step_25_custom_vars() {
    print_step_header 24 "Custom Environment Variables"
    
    cat << 'EOF'
Add custom environment variables for your services:

EOF

    if prompt_yes_no "Add custom environment variables?" "n"; then
        CONFIG_VALUES[CUSTOM_ENV_VARS]=""
        
        while true; do
            local var_name=$(prompt_with_default "Variable name (empty to finish)" "")
            [[ -z "$var_name" ]] && break
            
            local var_value=$(prompt_required "Variable value")
            CONFIG_VALUES[CUSTOM_ENV_VARS]+="${var_name}=${var_value}"$'\n'
        done
    fi
    
    log_success "Custom variables configured"
}

#==============================================================================
# STEP 26: EXPERIMENTAL FEATURES
#==============================================================================

step_26_experimental() {
    print_step_header 25 "Experimental Features"
    
    cat << 'EOF'
Enable experimental/beta features (use with caution):

EOF

    # Advanced context caching
    if prompt_yes_no "Enable advanced context caching?" "n"; then
        CONFIG_VALUES[EXPERIMENTAL_CACHING]="true"
    fi
    
    # Multi-modal support
    if prompt_yes_no "Enable multi-modal (vision) models?" "n"; then
        CONFIG_VALUES[EXPERIMENTAL_MULTIMODAL]="true"
    fi
    
    # Function calling
    if prompt_yes_no "Enable experimental function calling?" "n"; then
        CONFIG_VALUES[EXPERIMENTAL_FUNCTIONS]="true"
    fi
    
    # Memory optimization
    if prompt_yes_no "Enable aggressive memory optimization?" "n"; then
        CONFIG_VALUES[EXPERIMENTAL_MEMORY_OPT]="true"
    fi
    
    log_success "Experimental features configured"
}

#==============================================================================
# STEP 27: REVIEW & CONFIRM
#==============================================================================

step_27_review() {
    print_step_header 26 "Configuration Review"
    
    cat << 'EOF'
Please review your configuration:

EOF

    # Core services
    echo "=== CORE SERVICES ==="
    echo "Environment: ${CONFIG_VALUES[ENVIRONMENT]}"
    echo "Base Domain: ${CONFIG_VALUES[BASE_DOMAIN]}"
    echo "Proxy: ${CONFIG_VALUES[PROXY_TYPE]:-none}"
    echo
    echo "Services to install:"
    [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]] && echo "  ✓ Ollama (port ${CONFIG_VALUES[OLLAMA_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}" == "true" ]] && echo "  ✓ Open WebUI (port ${CONFIG_VALUES[OPEN_WEBUI_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]] && echo "  ✓ n8n (port ${CONFIG_VALUES[N8N_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]] && echo "  ✓ PostgreSQL (port ${CONFIG_VALUES[POSTGRES_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]] && echo "  ✓ Redis (port ${CONFIG_VALUES[REDIS_PORT]})"
    [[ "${CONFIG_VALUES[INSTALL_PORTAINER]}" == "true" ]] && echo "  ✓ Portainer (port ${CONFIG_VALUES[PORTAINER_PORT]})"
    echo
    
    # LLM Configuration
    echo "=== LLM CONFIGURATION ==="
    echo "Provider Mode: ${CONFIG_VALUES[LLM_PROVIDER_MODE]}"
    [[ "${CONFIG_VALUES[VECTOR_DB]}" != "none" ]] && echo "Vector DB: ${CONFIG_VALUES[VECTOR_DB]}"
    [[ "${CONFIG_VALUES[PRELOAD_MODELS]}" == "true" ]] && echo "Pre-load models: ${CONFIG_VALUES[OLLAMA_MODELS]}"
    echo
    
    # Authentication
    echo "=== AUTHENTICATION ==="
    echo "Auth Method: ${CONFIG_VALUES[AUTH_METHOD]}"
    [[ -n "${CONFIG_VALUES[ADMIN_USERNAME]}" ]] && echo "Admin User: ${CONFIG_VALUES[ADMIN_USERNAME]}"
    echo
    
    # Security
    echo "=== SECURITY ==="
    echo "SSL: ${CONFIG_VALUES[ENABLE_SSL]:-false}"
    [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]] && echo "SSL Type: ${CONFIG_VALUES[SSL_TYPE]}"
    [[ "${CONFIG_VALUES[RATE_LIMITING_ENABLED]}" == "true" ]] && echo "Rate Limiting: Enabled"
    [[ "${CONFIG_VALUES[INSTALL_FAIL2BAN]}" == "true" ]] && echo "Fail2ban: Enabled"
    echo
    
    # Monitoring
    if [[ "${CONFIG_VALUES[INSTALL_MONITORING]}" == "true" ]]; then
        echo "=== MONITORING ==="
        [[ "${CONFIG_VALUES[INSTALL_PROMETHEUS]}" == "true" ]] && echo "  ✓ Prometheus"
        [[ "${CONFIG_VALUES[INSTALL_GRAFANA]}" == "true" ]] && echo "  ✓ Grafana"
        [[ "${CONFIG_VALUES[INSTALL_LOKI]}" == "true" ]] && echo "  ✓ Loki"
        echo
    fi
    
    # Backups
    if [[ "${CONFIG_VALUES[ENABLE_BACKUPS]}" == "true" ]]; then
        echo "=== BACKUPS ==="
        echo "Schedule: ${CONFIG_VALUES[BACKUP_SCHEDULE]}"
        echo "Retention: ${CONFIG_VALUES[BACKUP_RETENTION_DAYS]} days"
        echo "Storage: ${CONFIG_VALUES[BACKUP_STORAGE]}"
        echo
    fi
    
    # Resources
    if [[ "${CONFIG_VALUES[ENABLE_GPU]}" == "true" ]]; then
        echo "=== GPU ==="
        echo "GPU Type: ${CONFIG_VALUES[GPU_TYPE]}"
        echo
    fi
    
    echo "=== NEXT STEPS ==="
    echo "1. Configuration files will be generated"
    echo "2. Docker Compose file will be created"
    echo "3. Services will be deployed"
    echo
    
    if ! prompt_yes_no "Configuration correct? Proceed with deployment?" "y"; then
        log_warning "Configuration review failed"
        if prompt_yes_no "Start wizard again?" "y"; then
            return 1  # Signal to restart wizard
        else
            log_info "Setup cancelled"
            exit 0
        fi
    fi
    
    log_success "Configuration confirmed"
    return 0
}

#==============================================================================
# CONFIGURATION FILE GENERATION
#==============================================================================

generate_env_file() {
    log_step "Generating .env file..."
    
    cat > "$ENV_FILE" << EOF
################################################################################
# AI Platform Automation - Environment Configuration
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# Environment: ${CONFIG_VALUES[ENVIRONMENT]}
################################################################################

#------------------------------------------------------------------------------
# PROJECT CONFIGURATION
#------------------------------------------------------------------------------
COMPOSE_PROJECT_NAME=${CONFIG_VALUES[COMPOSE_PROJECT_NAME]}
ENVIRONMENT=${CONFIG_VALUES[ENVIRONMENT]}
BASE_DOMAIN=${CONFIG_VALUES[BASE_DOMAIN]}
TIMEZONE=${CONFIG_VALUES[TIMEZONE]}

#------------------------------------------------------------------------------
# DIRECTORIES
#------------------------------------------------------------------------------
DATA_ROOT=${CONFIG_VALUES[DATA_ROOT]}
LOGS_ROOT=${CONFIG_VALUES[LOGS_ROOT]}
BACKUP_ROOT=${CONFIG_VALUES[BACKUP_ROOT]}
CONFIG_ROOT=${CONFIG_DIR}

#------------------------------------------------------------------------------
# NETWORK CONFIGURATION
#------------------------------------------------------------------------------
DOCKER_NETWORK_NAME=${CONFIG_VALUES[DOCKER_NETWORK_NAME]}
DOCKER_SUBNET=${CONFIG_VALUES[DOCKER_SUBNET]}
DOCKER_GATEWAY=${CONFIG_VALUES[DOCKER_GATEWAY]}
EOF

    # Add IPv6 if enabled
    if [[ "${CONFIG_VALUES[ENABLE_IPV6]}" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF
ENABLE_IPV6=true
DOCKER_SUBNET_IPV6=${CONFIG_VALUES[DOCKER_SUBNET_IPV6]}
EOF
    fi

    # Add DNS if configured
    if [[ "${CONFIG_VALUES[CUSTOM_DNS_ENABLED]}" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF
DNS_SERVERS=${CONFIG_VALUES[DNS_SERVERS]}
EOF
    fi

    # Ollama configuration
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF

#------------------------------------------------------------------------------
# OLLAMA CONFIGURATION
#------------------------------------------------------------------------------
OLLAMA_PORT=${CONFIG_VALUES[OLLAMA_PORT]}
OLLAMA_URL=${CONFIG_VALUES[OLLAMA_URL]}
OLLAMA_MODELS_DIR=${CONFIG_VALUES[OLLAMA_MODELS_DIR]}
OLLAMA_MAX_MEMORY=${CONFIG_VALUES[OLLAMA_MAX_MEMORY]}
OLLAMA_MAX_CPUS=${CONFIG_VALUES[OLLAMA_MAX_CPUS]}
OLLAMA_NUM_PARALLEL=${CONFIG_VALUES[OLLAMA_NUM_PARALLEL]:-1}
OLLAMA_MAX_LOADED_MODELS=${CONFIG_VALUES[OLLAMA_MAX_LOADED_MODELS]:-1}
OLLAMA_MODELS=${CONFIG_VALUES[OLLAMA_MODELS]:-}
OLLAMA_HEALTH_INTERVAL=${CONFIG_VALUES[OLLAMA_HEALTH_INTERVAL]:-30}
OLLAMA_HEALTH_TIMEOUT=${CONFIG_VALUES[OLLAMA_HEALTH_TIMEOUT]:-10}
OLLAMA_HEALTH_RETRIES=${CONFIG_VALUES[OLLAMA_HEALTH_RETRIES]:-3}
EOF
    fi

    # Open WebUI configuration
    if [[ "${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF

#------------------------------------------------------------------------------
# OPEN WEBUI CONFIGURATION
#------------------------------------------------------------------------------
OPEN_WEBUI_PORT=${CONFIG_VALUES[OPEN_WEBUI_PORT]}
WEBUI_URL=${CONFIG_VALUES[WEBUI_URL]}
WEBUI_MAX_MEMORY=${CONFIG_VALUES[WEBUI_MAX_MEMORY]:-2g}
WEBUI_MAX_CPUS=${CONFIG_VALUES[WEBUI_MAX_CPUS]:-2}
WEBUI_HEALTH_INTERVAL=${CONFIG_VALUES[WEBUI_HEALTH_INTERVAL]:-30}
WEBUI_HEALTH_TIMEOUT=${CONFIG_VALUES[WEBUI_HEALTH_TIMEOUT]:-5}
WEBUI_HEALTH_RETRIES=${CONFIG_VALUES[WEBUI_HEALTH_RETRIES]:-3}
EOF
    fi

    # n8n configuration
    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF

#------------------------------------------------------------------------------
# N8N CONFIGURATION
#------------------------------------------------------------------------------
N8N_PORT=${CONFIG_VALUES[N8N_PORT]}
N8N_URL=${CONFIG_VALUES[N8N_URL]}
N8N_MAX_MEMORY=${CONFIG_VALUES[N8N_MAX_MEMORY]:-2g}
N8N_MAX_CPUS=${CONFIG_VALUES[N8N_MAX_CPUS]:-2}
N8N_ENCRYPTION_KEY=${CONFIG_VALUES[ENCRYPTION_KEY]}
N8N_HEALTH_INTERVAL=${CONFIG_VALUES[N8N_HEALTH_INTERVAL]:-30}
N8N_HEALTH_TIMEOUT=${CONFIG_VALUES[N8N_HEALTH_TIMEOUT]:-5}
N8N_HEALTH_RETRIES=${CONFIG_VALUES[N8N_HEALTH_RETRIES]:-3}
EOF
    fi

    # PostgreSQL configuration
    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF

#------------------------------------------------------------------------------
# POSTGRESQL CONFIGURATION
#------------------------------------------------------------------------------
POSTGRES_PORT=${CONFIG_VALUES[POSTGRES_PORT]}
POSTGRES_DB=${CONFIG_VALUES[POSTGRES_DB]}
POSTGRES_USER=${CONFIG_VALUES[POSTGRES_USER]}
POSTGRES_PASSWORD=${CONFIG_VALUES[POSTGRES_PASSWORD]}
POSTGRES_MAX_MEMORY=${CONFIG_VALUES[POSTGRES_MAX_MEMORY]:-2g}
POSTGRES_MAX_CPUS=${CONFIG_VALUES[POSTGRES_MAX_CPUS]:-2}
POSTGRES_MAX_CONNECTIONS=${CONFIG_VALUES[POSTGRES_MAX_CONNECTIONS]:-100}
POSTGRES_SHARED_BUFFERS=${CONFIG_VALUES[POSTGRES_SHARED_BUFFERS]:-256MB}
POSTGRES_HEALTH_INTERVAL=${CONFIG_VALUES[POSTGRES_HEALTH_INTERVAL]:-10}
POSTGRES_HEALTH_TIMEOUT=${CONFIG_VALUES[POSTGRES_HEALTH_TIMEOUT]:-5}
POSTGRES_HEALTH_RETRIES=${CONFIG_VALUES[POSTGRES_HEALTH_RETRIES]:-5}
EOF
    fi

    # Redis configuration
    if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF

#------------------------------------------------------------------------------
# REDIS CONFIGURATION
#------------------------------------------------------------------------------
REDIS_PORT=${CONFIG_VALUES[REDIS_PORT]}
REDIS_PASSWORD=${CONFIG_VALUES[REDIS_PASSWORD]}
REDIS_MAX_MEMORY=${CONFIG_VALUES[REDIS_MAX_MEMORY]:-512mb}
REDIS_MAXMEMORY_POLICY=${CONFIG_VALUES[REDIS_MAXMEMORY_POLICY]:-allkeys-lru}
REDIS_HEALTH_INTERVAL=${CONFIG_VALUES[REDIS_HEALTH_INTERVAL]:-10}
REDIS_HEALTH_TIMEOUT=${CONFIG_VALUES[REDIS_HEALTH_TIMEOUT]:-3}
REDIS_HEALTH_RETRIES=${CONFIG_VALUES[REDIS_HEALTH_RETRIES]:-5}
EOF
    fi

    # SSL configuration
    if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF

#------------------------------------------------------------------------------
# SSL/TLS CONFIGURATION
#------------------------------------------------------------------------------
ENABLE_SSL=true
SSL_TYPE=${CONFIG_VALUES[SSL_TYPE]}
EOF
        
        if [[ "${CONFIG_VALUES[SSL_TYPE]}" == "letsencrypt" ]]; then
            cat >> "$ENV_FILE" << EOF
SSL_EMAIL=${CONFIG_VALUES[SSL_EMAIL]}
EOF
        elif [[ "${CONFIG_VALUES[SSL_TYPE]}" == "custom" ]]; then
            cat >> "$ENV_FILE" << EOF
SSL_CERT_PATH=${CONFIG_VALUES[SSL_CERT_PATH]}
SSL_KEY_PATH=${CONFIG_VALUES[SSL_KEY_PATH]}
EOF
        fi
    fi

    # Authentication
    cat >> "$ENV_FILE" << EOF

#------------------------------------------------------------------------------
# AUTHENTICATION
#------------------------------------------------------------------------------
AUTH_METHOD=${CONFIG_VALUES[AUTH_METHOD]}
EOF

    if [[ "${CONFIG_VALUES[AUTH_TYPE]}" == "local" ]]; then
        cat >> "$ENV_FILE" << EOF
ADMIN_USERNAME=${CONFIG_VALUES[ADMIN_USERNAME]}
ADMIN_PASSWORD=${CONFIG_VALUES[ADMIN_PASSWORD]}
ADMIN_EMAIL=${CONFIG_VALUES[ADMIN_EMAIL]}
EOF
    elif [[ "${CONFIG_VALUES[AUTH_TYPE]}" == "ldap" ]]; then
        cat >> "$ENV_FILE" << EOF
LDAP_URL=${CONFIG_VALUES[LDAP_URL]}
LDAP_BIND_DN=${CONFIG_VALUES[LDAP_BIND_DN]}
LDAP_BIND_PASSWORD=${CONFIG_VALUES[LDAP_BIND_PASSWORD]}
LDAP_SEARCH_BASE=${CONFIG_VALUES[LDAP_SEARCH_BASE]}
LDAP_USER_FILTER=${CONFIG_VALUES[LDAP_USER_FILTER]}
EOF
    fi

    # Security
    cat >> "$ENV_FILE" << EOF

#------------------------------------------------------------------------------
# SECURITY
#------------------------------------------------------------------------------
JWT_SECRET=${CONFIG_VALUES[JWT_SECRET]}
SESSION_SECRET=${CONFIG_VALUES[SESSION_SECRET]}
ENCRYPTION_KEY=${CONFIG_VALUES[ENCRYPTION_KEY]}
EOF

    if [[ "${CONFIG_VALUES[API_KEY_ENABLED]}" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF
API_KEY=${CONFIG_VALUES[API_KEY]}
EOF
    fi

    # Monitoring
    if [[ "${CONFIG_VALUES[INSTALL_MONITORING]}" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF

#------------------------------------------------------------------------------
# MONITORING
#------------------------------------------------------------------------------
EOF
        if [[ "${CONFIG_VALUES[INSTALL_PROMETHEUS]}" == "true" ]]; then
            cat >> "$ENV_FILE" << EOF
PROMETHEUS_PORT=${CONFIG_VALUES[PROMETHEUS_PORT]}
PROMETHEUS_RETENTION=${CONFIG_VALUES[PROMETHEUS_RETENTION]}d
EOF
        fi
        
        if [[ "${CONFIG_VALUES[INSTALL_GRAFANA]}" == "true" ]]; then
            cat >> "$ENV_FILE" << EOF
GRAFANA_PORT=${CONFIG_VALUES[GRAFANA_PORT]}
GRAFANA_ADMIN_PASSWORD=${CONFIG_VALUES[GRAFANA_ADMIN_PASSWORD]}
EOF
        fi
    fi

    # Logging
    cat >> "$ENV_FILE" << EOF

#------------------------------------------------------------------------------
# LOGGING
#------------------------------------------------------------------------------
LOG_LEVEL=${CONFIG_VALUES[LOG_LEVEL]}
LOG_RETENTION_DAYS=${CONFIG_VALUES[LOG_RETENTION_DAYS]}
STRUCTURED_LOGGING=${CONFIG_VALUES[STRUCTURED_LOGGING]:-false}
EOF

    # Backups
    if [[ "${CONFIG_VALUES[ENABLE_BACKUPS]}" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF

#------------------------------------------------------------------------------
# BACKUP CONFIGURATION
#------------------------------------------------------------------------------
ENABLE_BACKUPS=true
BACKUP_SCHEDULE=${CONFIG_VALUES[BACKUP_SCHEDULE]}
BACKUP_RETENTION_DAYS=${CONFIG_VALUES[BACKUP_RETENTION_DAYS]}
BACKUP_COMPRESSION=${CONFIG_VALUES[BACKUP_COMPRESSION]:-false}
EOF
        
        if [[ "${CONFIG_VALUES[BACKUP_ENCRYPTION]}" == "true" ]]; then
            cat >> "$ENV_FILE" << EOF
BACKUP_ENCRYPTION=true
BACKUP_ENCRYPTION_KEY=${CONFIG_VALUES[BACKUP_ENCRYPTION_KEY]}
EOF
        fi
    fi

    # GPU configuration
    if [[ "${CONFIG_VALUES[ENABLE_GPU]}" == "true" ]]; then
        cat >> "$ENV_FILE" << EOF

#------------------------------------------------------------------------------
# GPU CONFIGURATION
#------------------------------------------------------------------------------
ENABLE_GPU=true
GPU_TYPE=${CONFIG_VALUES[GPU_TYPE]}
EOF
    fi

    # Custom variables
    if [[ -n "${CONFIG_VALUES[CUSTOM_ENV_VARS]}" ]]; then
        cat >> "$ENV_FILE" << EOF

#------------------------------------------------------------------------------
# CUSTOM ENVIRONMENT VARIABLES
#------------------------------------------------------------------------------
${CONFIG_VALUES[CUSTOM_ENV_VARS]}
EOF
    fi

    cat >> "$ENV_FILE" << EOF

#------------------------------------------------------------------------------
# END OF CONFIGURATION
#------------------------------------------------------------------------------
EOF

    chmod 600 "$ENV_FILE"
    log_success ".env file generated"
}

#==============================================================================
# CONFIGURATION SUMMARY
#==============================================================================

display_configuration_summary() {
    cat << EOF

================================================================================
                      CONFIGURATION SUMMARY
================================================================================

Configuration files generated:
  • ${ENV_FILE}
  • ${DOCKER_COMPOSE_FILE}

Services configured:
EOF

    [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]] && echo "  ✓ Ollama - http://localhost:${CONFIG_VALUES[OLLAMA_PORT]}"
    [[ "${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}" == "true" ]] && echo "  ✓ Open WebUI - ${CONFIG_VALUES[WEBUI_URL]}"
    [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]] && echo "  ✓ n8n - ${CONFIG_VALUES[N8N_URL]}"
    [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]] && echo "  ✓ PostgreSQL - localhost:${CONFIG_VALUES[POSTGRES_PORT]}"
    [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]] && echo "  ✓ Redis - localhost:${CONFIG_VALUES[REDIS_PORT]}"
    [[ "${CONFIG_VALUES[INSTALL_PORTAINER]}" == "true" ]] && echo "  ✓ Portainer - https://localhost:${CONFIG_VALUES[PORTAINER_PORT]}"

    cat << EOF

Important credentials saved to .env file:
EOF

    [[ -n "${CONFIG_VALUES[ADMIN_PASSWORD]}" ]] && echo "  • Admin password: ${CONFIG_VALUES[ADMIN_PASSWORD]}"
    [[ -n "${CONFIG_VALUES[POSTGRES_PASSWORD]}" ]] && echo "  • PostgreSQL password: ${CONFIG_VALUES[POSTGRES_PASSWORD]}"
    [[ -n "${CONFIG_VALUES[REDIS_PASSWORD]}" ]] && echo "  • Redis password: ${CONFIG_VALUES[REDIS_PASSWORD]}"
    [[ -n "${CONFIG_VALUES[GRAFANA_ADMIN_PASSWORD]}" ]] && echo "  • Grafana password: ${CONFIG_VALUES[GRAFANA_ADMIN_PASSWORD]}"

    cat << EOF

Next steps:
  1. Review configuration files
  2. Deploy services: docker-compose up -d
  3. Access services via configured URLs
  4. Check logs: docker-compose logs -f

================================================================================
EOF
}

#==============================================================================
# END OF PART 3/4
#==============================================================================
#!/bin/bash
################################################################################
# AI Platform Automation - System Setup Script  
# Part 4/4: Docker Compose Generation, Deployment & Main Execution (CORRECTED)
################################################################################

#==============================================================================
# DOCKER COMPOSE FILE GENERATION
#==============================================================================

generate_docker_compose() {
    log_step "Generating docker-compose.yml..."
    
    cat > "$DOCKER_COMPOSE_FILE" << 'EOF'
################################################################################
# AI Platform Automation - Docker Compose Configuration
# Generated by setup wizard
################################################################################

version: '3.8'

networks:
  aiplatform:
    driver: bridge
    ipam:
      config:
        - subnet: ${DOCKER_SUBNET}
          gateway: ${DOCKER_GATEWAY}
EOF

    # Add IPv6 if enabled
    if [[ "${CONFIG_VALUES[ENABLE_IPV6]}" == "true" ]]; then
        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
        - subnet: ${DOCKER_SUBNET_IPV6}
    enable_ipv6: true
EOF
    fi

    cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'

volumes:
  ollama_data:
    driver: local
  postgres_data:
    driver: local
  redis_data:
    driver: local
  n8n_data:
    driver: local
  portainer_data:
    driver: local
  prometheus_data:
    driver: local
  grafana_data:
    driver: local
EOF

    # Add vector DB volumes if configured
    if [[ "${CONFIG_VALUES[VECTOR_DB]}" == "qdrant" ]]; then
        echo "  qdrant_data:" >> "$DOCKER_COMPOSE_FILE"
        echo "    driver: local" >> "$DOCKER_COMPOSE_FILE"
    elif [[ "${CONFIG_VALUES[VECTOR_DB]}" == "chroma" ]]; then
        echo "  chroma_data:" >> "$DOCKER_COMPOSE_FILE"
        echo "    driver: local" >> "$DOCKER_COMPOSE_FILE"
    elif [[ "${CONFIG_VALUES[VECTOR_DB]}" == "weaviate" ]]; then
        echo "  weaviate_data:" >> "$DOCKER_COMPOSE_FILE"
        echo "    driver: local" >> "$DOCKER_COMPOSE_FILE"
    fi

    cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'

services:
EOF

    # PostgreSQL service
    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
  postgres:
    image: postgres:16-alpine
    container_name: ${COMPOSE_PROJECT_NAME}_postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_INITDB_ARGS: "-E UTF8"
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ${CONFIG_ROOT}/postgres:/docker-entrypoint-initdb.d:ro
    ports:
      - "${POSTGRES_PORT}:5432"
    networks:
      - aiplatform
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: ${POSTGRES_HEALTH_INTERVAL:-10}s
      timeout: ${POSTGRES_HEALTH_TIMEOUT:-5}s
      retries: ${POSTGRES_HEALTH_RETRIES:-5}
      start_period: 30s
    deploy:
      resources:
        limits:
          memory: ${POSTGRES_MAX_MEMORY:-2g}
          cpus: '${POSTGRES_MAX_CPUS:-2}'
        reservations:
          memory: 512m
    logging:
      driver: "json-file"
      options:
        max-size: "${LOG_MAX_SIZE:-100m}"
        max-file: "${LOG_MAX_FILES:-10}"

EOF
    fi

    # Redis service
    if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
  redis:
    image: redis:7-alpine
    container_name: ${COMPOSE_PROJECT_NAME}_redis
    restart: unless-stopped
    command: >
      redis-server
      --requirepass ${REDIS_PASSWORD}
      --maxmemory ${REDIS_MAX_MEMORY:-512mb}
      --maxmemory-policy ${REDIS_MAXMEMORY_POLICY:-allkeys-lru}
      --save 60 1
      --loglevel warning
    volumes:
      - redis_data:/data
    ports:
      - "${REDIS_PORT}:6379"
    networks:
      - aiplatform
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: ${REDIS_HEALTH_INTERVAL:-10}s
      timeout: ${REDIS_HEALTH_TIMEOUT:-3}s
      retries: ${REDIS_HEALTH_RETRIES:-5}
      start_period: 10s
    deploy:
      resources:
        limits:
          memory: ${REDIS_MAX_MEMORY:-512mb}
        reservations:
          memory: 128m
    logging:
      driver: "json-file"
      options:
        max-size: "${LOG_MAX_SIZE:-100m}"
        max-file: "${LOG_MAX_FILES:-10}"

EOF
    fi

    # Ollama service
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
  ollama:
    image: ollama/ollama:latest
    container_name: ${COMPOSE_PROJECT_NAME}_ollama
    restart: unless-stopped
    environment:
      - OLLAMA_NUM_PARALLEL=${OLLAMA_NUM_PARALLEL:-1}
      - OLLAMA_MAX_LOADED_MODELS=${OLLAMA_MAX_LOADED_MODELS:-1}
EOF

        if [[ "${CONFIG_VALUES[ENABLE_GPU]}" == "true" ]]; then
            if [[ "${CONFIG_VALUES[GPU_TYPE]}" == "nvidia" ]]; then
                cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
        limits:
          memory: ${OLLAMA_MAX_MEMORY}
          cpus: '${OLLAMA_MAX_CPUS}'
EOF
            elif [[ "${CONFIG_VALUES[GPU_TYPE]}" == "amd" ]]; then
                cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
    devices:
      - /dev/kfd
      - /dev/dri
    group_add:
      - video
    deploy:
      resources:
        limits:
          memory: ${OLLAMA_MAX_MEMORY}
          cpus: '${OLLAMA_MAX_CPUS}'
EOF
            fi
        else
            cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
    deploy:
      resources:
        limits:
          memory: ${OLLAMA_MAX_MEMORY}
          cpus: '${OLLAMA_MAX_CPUS}'
        reservations:
          memory: 2g
EOF
        fi

        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
    volumes:
      - ollama_data:/root/.ollama
    ports:
      - "${OLLAMA_PORT}:11434"
    networks:
      - aiplatform
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:11434/api/tags || exit 1"]
      interval: ${OLLAMA_HEALTH_INTERVAL:-30}s
      timeout: ${OLLAMA_HEALTH_TIMEOUT:-10}s
      retries: ${OLLAMA_HEALTH_RETRIES:-3}
      start_period: 60s
    logging:
      driver: "json-file"
      options:
        max-size: "${LOG_MAX_SIZE:-100m}"
        max-file: "${LOG_MAX_FILES:-10}"

EOF
    fi

    # Open WebUI service
    if [[ "${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}" == "true" ]]; then
        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: ${COMPOSE_PROJECT_NAME}_open_webui
    restart: unless-stopped
    environment:
      - OLLAMA_BASE_URL=${OLLAMA_URL}
      - WEBUI_SECRET_KEY=${SESSION_SECRET}
EOF

        if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
            cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
      - DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
EOF
        fi

        if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
            cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
      - REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379/0
EOF
        fi

        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
      - WEBUI_AUTH=${WEBUI_AUTH:-true}
    volumes:
      - ${DATA_ROOT}/open-webui:/app/backend/data
    ports:
      - "${OPEN_WEBUI_PORT}:8080"
    networks:
      - aiplatform
    depends_on:
EOF

        if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
            echo "      - ollama" >> "$DOCKER_COMPOSE_FILE"
        fi
        if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
            echo "      - postgres" >> "$DOCKER_COMPOSE_FILE"
        fi
        if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
            echo "      - redis" >> "$DOCKER_COMPOSE_FILE"
        fi

        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: ${WEBUI_HEALTH_INTERVAL:-30}s
      timeout: ${WEBUI_HEALTH_TIMEOUT:-5}s
      retries: ${WEBUI_HEALTH_RETRIES:-3}
      start_period: 30s
    deploy:
      resources:
        limits:
          memory: ${WEBUI_MAX_MEMORY:-2g}
          cpus: '${WEBUI_MAX_CPUS:-2}'
        reservations:
          memory: 512m
    logging:
      driver: "json-file"
      options:
        max-size: "${LOG_MAX_SIZE:-100m}"
        max-file: "${LOG_MAX_FILES:-10}"

EOF
    fi

    # n8n service
    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
  n8n:
    image: n8nio/n8n:latest
    container_name: ${COMPOSE_PROJECT_NAME}_n8n
    restart: unless-stopped
    environment:
      - N8N_HOST=${BASE_DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=${N8N_PROTOCOL:-http}
      - WEBHOOK_URL=${N8N_WEBHOOK_URL}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD}
EOF

        if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
            cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
EOF
        fi

        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
      - N8N_LOG_LEVEL=${LOG_LEVEL:-info}
      - N8N_LOG_OUTPUT=console
    volumes:
      - n8n_data:/home/node/.n8n
    ports:
      - "${N8N_PORT}:5678"
    networks:
      - aiplatform
    depends_on:
EOF

        if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
            echo "      - postgres" >> "$DOCKER_COMPOSE_FILE"
        fi
        if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
            echo "      - redis" >> "$DOCKER_COMPOSE_FILE"
        fi

        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:5678/healthz"]
      interval: ${N8N_HEALTH_INTERVAL:-30}s
      timeout: ${N8N_HEALTH_TIMEOUT:-5}s
      retries: ${N8N_HEALTH_RETRIES:-3}
      start_period: 30s
    deploy:
      resources:
        limits:
          memory: ${N8N_MAX_MEMORY:-2g}
          cpus: '${N8N_MAX_CPUS:-2}'
        reservations:
          memory: 512m
    logging:
      driver: "json-file"
      options:
        max-size: "${LOG_MAX_SIZE:-100m}"
        max-file: "${LOG_MAX_FILES:-10}"

EOF
    fi

    # Vector Database - Qdrant
    if [[ "${CONFIG_VALUES[VECTOR_DB]}" == "qdrant" ]]; then
        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
  qdrant:
    image: qdrant/qdrant:latest
    container_name: ${COMPOSE_PROJECT_NAME}_qdrant
    restart: unless-stopped
    environment:
      - QDRANT__SERVICE__GRPC_PORT=6334
    volumes:
      - qdrant_data:/qdrant/storage
    ports:
      - "${QDRANT_PORT:-6333}:6333"
      - "${QDRANT_GRPC_PORT:-6334}:6334"
    networks:
      - aiplatform
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6333/health"]
      interval: 30s
      timeout: 5s
      retries: 3
    deploy:
      resources:
        limits:
          memory: ${QDRANT_MAX_MEMORY:-2g}
        reservations:
          memory: 512m
    logging:
      driver: "json-file"
      options:
        max-size: "${LOG_MAX_SIZE:-100m}"
        max-file: "${LOG_MAX_FILES:-10}"

EOF
    fi

    # Vector Database - Chroma
    if [[ "${CONFIG_VALUES[VECTOR_DB]}" == "chroma" ]]; then
        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
  chroma:
    image: chromadb/chroma:latest
    container_name: ${COMPOSE_PROJECT_NAME}_chroma
    restart: unless-stopped
    volumes:
      - chroma_data:/chroma/chroma
    ports:
      - "${CHROMA_PORT:-8000}:8000"
    networks:
      - aiplatform
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/api/v1/heartbeat"]
      interval: 30s
      timeout: 5s
      retries: 3
    deploy:
      resources:
        limits:
          memory: ${CHROMA_MAX_MEMORY:-2g}
        reservations:
          memory: 512m
    logging:
      driver: "json-file"
      options:
        max-size: "${LOG_MAX_SIZE:-100m}"
        max-file: "${LOG_MAX_FILES:-10}"

EOF
    fi

    # LiteLLM Proxy (for external providers)
    if [[ "${CONFIG_VALUES[INSTALL_LITELLM]}" == "true" ]]; then
        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: ${COMPOSE_PROJECT_NAME}_litellm
    restart: unless-stopped
    environment:
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
      - DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
      - REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379/1
    volumes:
      - ${CONFIG_ROOT}/litellm/config.yaml:/app/config.yaml:ro
    ports:
      - "${LITELLM_PORT:-4000}:4000"
    networks:
      - aiplatform
    depends_on:
      - postgres
      - redis
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 5s
      retries: 3
    deploy:
      resources:
        limits:
          memory: 1g
        reservations:
          memory: 256m
    logging:
      driver: "json-file"
      options:
        max-size: "${LOG_MAX_SIZE:-100m}"
        max-file: "${LOG_MAX_FILES:-10}"

EOF
    fi

    # Nginx Proxy
    if [[ "${CONFIG_VALUES[PROXY_TYPE]}" == "nginx" ]]; then
        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
  nginx:
    image: nginx:alpine
    container_name: ${COMPOSE_PROJECT_NAME}_nginx
    restart: unless-stopped
    volumes:
      - ${CONFIG_ROOT}/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ${CONFIG_ROOT}/nginx/conf.d:/etc/nginx/conf.d:ro
      - ${DATA_ROOT}/nginx/cache:/var/cache/nginx
      - ${LOGS_ROOT}/nginx:/var/log/nginx
EOF

        if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]]; then
            cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
      - ${CONFIG_ROOT}/ssl/certs:/etc/nginx/ssl:ro
EOF
        fi

        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
    ports:
      - "80:80"
      - "443:443"
    networks:
      - aiplatform
    depends_on:
EOF

        [[ "${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}" == "true" ]] && echo "      - open-webui" >> "$DOCKER_COMPOSE_FILE"
        [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]] && echo "      - n8n" >> "$DOCKER_COMPOSE_FILE"
        [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]] && echo "      - ollama" >> "$DOCKER_COMPOSE_FILE"

        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost/health"]
      interval: 10s
      timeout: 3s
      retries: 3
    deploy:
      resources:
        limits:
          memory: ${NGINX_MAX_MEMORY:-512m}
    logging:
      driver: "json-file"
      options:
        max-size: "${LOG_MAX_SIZE:-100m}"
        max-file: "${LOG_MAX_FILES:-10}"

EOF
    fi

    # Traefik Proxy
    if [[ "${CONFIG_VALUES[PROXY_TYPE]}" == "traefik" ]]; then
        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
  traefik:
    image: traefik:v3.0
    container_name: ${COMPOSE_PROJECT_NAME}_traefik
    restart: unless-stopped
    command:
      - "--api.dashboard=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
EOF

        if [[ "${CONFIG_VALUES[SSL_TYPE]}" == "letsencrypt" ]]; then
            cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
      - "--certificatesresolvers.letsencrypt.acme.email=${SSL_EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.tlschallenge=true"
EOF
        fi

        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ${DATA_ROOT}/traefik/letsencrypt:/letsencrypt
    ports:
      - "80:80"
      - "443:443"
      - "${TRAEFIK_DASHBOARD_PORT:-8080}:8080"
    networks:
      - aiplatform
    healthcheck:
      test: ["CMD", "traefik", "healthcheck"]
      interval: 10s
      timeout: 3s
      retries: 3
    deploy:
      resources:
        limits:
          memory: 512m
    logging:
      driver: "json-file"
      options:
        max-size: "${LOG_MAX_SIZE:-100m}"
        max-file: "${LOG_MAX_FILES:-10}"

EOF
    fi

    # Portainer
    if [[ "${CONFIG_VALUES[INSTALL_PORTAINER]}" == "true" ]]; then
        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
  portainer:
    image: portainer/portainer-ce:latest
    container_name: ${COMPOSE_PROJECT_NAME}_portainer
    restart: unless-stopped
    command: -H unix:///var/run/docker.sock
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    ports:
      - "${PORTAINER_PORT:-9443}:9443"
      - "8000:8000"
    networks:
      - aiplatform
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:9000/api/status"]
      interval: 30s
      timeout: 5s
      retries: 3
    deploy:
      resources:
        limits:
          memory: 512m
    logging:
      driver: "json-file"
      options:
        max-size: "${LOG_MAX_SIZE:-100m}"
        max-file: "${LOG_MAX_FILES:-10}"

EOF
    fi

    # Prometheus
    if [[ "${CONFIG_VALUES[INSTALL_PROMETHEUS]}" == "true" ]]; then
        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
  prometheus:
    image: prom/prometheus:latest
    container_name: ${COMPOSE_PROJECT_NAME}_prometheus
    restart: unless-stopped
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=${PROMETHEUS_RETENTION:-15}d'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
    volumes:
      - ${CONFIG_ROOT}/prometheus:/etc/prometheus
      - prometheus_data:/prometheus
    ports:
      - "${PROMETHEUS_PORT:-9090}:9090"
    networks:
      - aiplatform
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 5s
      retries: 3
    deploy:
      resources:
        limits:
          memory: ${PROMETHEUS_MAX_MEMORY:-2g}
    logging:
      driver: "json-file"
      options:
        max-size: "${LOG_MAX_SIZE:-100m}"
        max-file: "${LOG_MAX_FILES:-10}"

EOF
    fi

    # Grafana
    if [[ "${CONFIG_VALUES[INSTALL_GRAFANA]}" == "true" ]]; then
        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
  grafana:
    image: grafana/grafana:latest
    container_name: ${COMPOSE_PROJECT_NAME}_grafana
    restart: unless-stopped
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
      - GF_INSTALL_PLUGINS=redis-datasource
      - GF_SERVER_ROOT_URL=${GRAFANA_URL}
    volumes:
      - grafana_data:/var/lib/grafana
      - ${CONFIG_ROOT}/grafana/provisioning:/etc/grafana/provisioning
    ports:
      - "${GRAFANA_PORT:-3000}:3000"
    networks:
      - aiplatform
    depends_on:
      - prometheus
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 5s
      retries: 3
    deploy:
      resources:
        limits:
          memory: 1g
    logging:
      driver: "json-file"
      options:
        max-size: "${LOG_MAX_SIZE:-100m}"
        max-file: "${LOG_MAX_FILES:-10}"

EOF
    fi

    # Watchtower (auto-updates)
    if [[ "${CONFIG_VALUES[INSTALL_WATCHTOWER]}" == "true" ]]; then
        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
  watchtower:
    image: containrrr/watchtower:latest
    container_name: ${COMPOSE_PROJECT_NAME}_watchtower
    restart: unless-stopped
    environment:
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_POLL_INTERVAL=86400
      - WATCHTOWER_INCLUDE_STOPPED=false
      - WATCHTOWER_REVIVE_STOPPED=false
EOF

        if [[ "${CONFIG_VALUES[WATCHTOWER_AUTO_UPDATE]}" != "true" ]]; then
            cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
      - WATCHTOWER_MONITOR_ONLY=true
EOF
        fi

        cat >> "$DOCKER_COMPOSE_FILE" << 'EOF'
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - aiplatform
    logging:
      driver: "json-file"
      options:
        max-size: "${LOG_MAX_SIZE:-100m}"
        max-file: "${LOG_MAX_FILES:-10}"

EOF
    fi

    log_success "docker-compose.yml generated"
}

#==============================================================================
# NGINX CONFIGURATION GENERATION
#==============================================================================

generate_nginx_config() {
    if [[ "${CONFIG_VALUES[PROXY_TYPE]}" != "nginx" ]]; then
        return 0
    fi
    
    log_step "Generating Nginx configuration..."
    
    local nginx_dir="${CONFIG_DIR}/nginx"
    mkdir -p "$nginx_dir/conf.d"
    
    # Main nginx.conf
    cat > "$nginx_dir/nginx.conf" << EOF
user nginx;
worker_processes ${CONFIG_VALUES[PROXY_WORKER_PROCESSES]:-auto};
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections ${CONFIG_VALUES[PROXY_WORKER_CONNECTIONS]:-1024};
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout ${CONFIG_VALUES[KEEPALIVE_TIMEOUT]:-65};
    types_hash_max_size 2048;
    client_max_body_size 100M;

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
    limit_req_zone \$binary_remote_addr zone=general:10m rate=${CONFIG_VALUES[RATE_LIMIT_REQUESTS]:-60}r/m;
    limit_req_status 429;

    include /etc/nginx/conf.d/*.conf;
}
EOF

    # Health check endpoint
    cat > "$nginx_dir/conf.d/health.conf" << 'EOF'
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

    # Open WebUI configuration
    if [[ "${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}" == "true" ]]; then
        cat > "$nginx_dir/conf.d/openwebui.conf" << EOF
upstream openwebui {
    server open-webui:8080;
    keepalive 32;
}

server {
    listen 80;
    server_name ${CONFIG_VALUES[WEBUI_DOMAIN]:-webui.${CONFIG_VALUES[BASE_DOMAIN]}};

EOF

        if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]]; then
            cat >> "$nginx_dir/conf.d/openwebui.conf" << EOF
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${CONFIG_VALUES[WEBUI_DOMAIN]:-webui.${CONFIG_VALUES[BASE_DOMAIN]}};

    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

EOF
        fi

        cat >> "$nginx_dir/conf.d/openwebui.conf" << 'EOF'
    client_max_body_size 100M;

    location / {
        proxy_pass http://openwebui;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        proxy_request_buffering off;
    }

    limit_req zone=general burst=${CONFIG_VALUES[RATE_LIMIT_BURST]:-10} nodelay;
}
EOF
    fi

    # n8n configuration
    if [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]]; then
        cat > "$nginx_dir/conf.d/n8n.conf" << EOF
upstream n8n {
    server n8n:5678;
    keepalive 32;
}

server {
    listen 80;
    server_name ${CONFIG_VALUES[N8N_DOMAIN]:-n8n.${CONFIG_VALUES[BASE_DOMAIN]}};

EOF

        if [[ "${CONFIG_VALUES[ENABLE_SSL]}" == "true" ]]; then
            cat >> "$nginx_dir/conf.d/n8n.conf" << EOF
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${CONFIG_VALUES[N8N_DOMAIN]:-n8n.${CONFIG_VALUES[BASE_DOMAIN]}};

    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

EOF
        fi

        cat >> "$nginx_dir/conf.d/n8n.conf" << 'EOF'
    location / {
        proxy_pass http://n8n;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        chunked_transfer_encoding off;
        proxy_buffering off;
        proxy_cache_bypass $http_upgrade;
    }

    limit_req zone=general burst=${CONFIG_VALUES[RATE_LIMIT_BURST]:-10} nodelay;
}
EOF
    fi

    log_success "Nginx configuration generated"
}

#==============================================================================
# PROMETHEUS CONFIGURATION
#==============================================================================

generate_prometheus_config() {
    if [[ "${CONFIG_VALUES[INSTALL_PROMETHEUS]}" != "true" ]]; then
        return 0
    fi
    
    log_step "Generating Prometheus configuration..."
    
    local prom_dir="${CONFIG_DIR}/prometheus"
    mkdir -p "$prom_dir"
    
    cat > "$prom_dir/prometheus.yml" << 'EOF'
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

  - job_name: 'docker'
    static_configs:
      - targets: ['host.docker.internal:9323']

EOF

    if [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]]; then
        cat >> "$prom_dir/prometheus.yml" << 'EOF'
  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres:5432']

EOF
    fi

    if [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]]; then
        cat >> "$prom_dir/prometheus.yml" << 'EOF'
  - job_name: 'redis'
    static_configs:
      - targets: ['redis:6379']

EOF
    fi

    log_success "Prometheus configuration generated"
}

#==============================================================================
# LITELLM CONFIGURATION
#==============================================================================

generate_litellm_config() {
    if [[ "${CONFIG_VALUES[INSTALL_LITELLM]}" != "true" ]]; then
        return 0
    fi
    
    log_step "Generating LiteLLM configuration..."
    
    local litellm_dir="${CONFIG_DIR}/litellm"
    mkdir -p "$litellm_dir"
    
    cat > "$litellm_dir/config.yaml" << EOF
model_list:
EOF

    # Add local Ollama if installed
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]]; then
        cat >> "$litellm_dir/config.yaml" << 'EOF'
  - model_name: ollama/*
    litellm_params:
      model: ollama/*
      api_base: http://ollama:11434

EOF
    fi

    # Add external providers based on configuration
    if [[ "${CONFIG_VALUES[LLM_PROVIDER_MODE]}" == "external" ]] || [[ "${CONFIG_VALUES[LLM_PROVIDER_MODE]}" == "hybrid" ]]; then
        
        # OpenAI
        if [[ -n "${CONFIG_VALUES[OPENAI_API_KEY]}" ]]; then
            cat >> "$litellm_dir/config.yaml" << EOF
  - model_name: gpt-4
    litellm_params:
      model: openai/gpt-4
      api_key: ${CONFIG_VALUES[OPENAI_API_KEY]}

  - model_name: gpt-3.5-turbo
    litellm_params:
      model: openai/gpt-3.5-turbo
      api_key: ${CONFIG_VALUES[OPENAI_API_KEY]}

EOF
        fi

        # Anthropic
        if [[ -n "${CONFIG_VALUES[ANTHROPIC_API_KEY]}" ]]; then
            cat >> "$litellm_dir/config.yaml" << EOF
  - model_name: claude-3-opus
    litellm_params:
      model: anthropic/claude-3-opus-20240229
      api_key: ${CONFIG_VALUES[ANTHROPIC_API_KEY]}

  - model_name: claude-3-sonnet
    litellm_params:
      model: anthropic/claude-3-sonnet-20240229
      api_key: ${CONFIG_VALUES[ANTHROPIC_API_KEY]}

EOF
        fi

        # Google
        if [[ -n "${CONFIG_VALUES[GOOGLE_API_KEY]}" ]]; then
            cat >> "$litellm_dir/config.yaml" << EOF
  - model_name: gemini-pro
    litellm_params:
      model: gemini/gemini-pro
      api_key: ${CONFIG_VALUES[GOOGLE_API_KEY]}

EOF
        fi
    fi

    cat >> "$litellm_dir/config.yaml" << 'EOF'

litellm_settings:
  drop_params: true
  set_verbose: false
  request_timeout: 600
  num_retries: 3

general_settings:
  master_key: ${LITELLM_MASTER_KEY}
  database_url: ${DATABASE_URL}
  ui_access_mode: "admin_only"
EOF

    log_success "LiteLLM configuration generated"
}

#==============================================================================
# DIRECTORY STRUCTURE CREATION
#==============================================================================

create_directory_structure() {
    log_step "Creating directory structure..."
    
    local dirs=(
        "$DATA_DIR"
        "$LOGS_DIR"
        "$BACKUP_DIR"
        "$CONFIG_DIR"
        "${CONFIG_DIR}/nginx/conf.d"
        "${CONFIG_DIR}/prometheus"
        "${CONFIG_DIR}/grafana/provisioning/datasources"
        "${CONFIG_DIR}/grafana/provisioning/dashboards"
        "${CONFIG_DIR}/litellm"
        "${CONFIG_DIR}/ssl/certs"
        "${CONFIG_DIR}/postgres"
        "${DATA_DIR}/ollama/models"
        "${DATA_DIR}/open-webui"
        "${DATA_DIR}/n8n"
        "${DATA_DIR}/nginx/cache"
        "${DATA_DIR}/traefik/letsencrypt"
        "${LOGS_DIR}/nginx"
        "${LOGS_DIR}/postgres"
        "${LOGS_DIR}/redis"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_info "Created directory: $dir"
        fi
    done
    
    # Set permissions
    chmod 700 "${CONFIG_DIR}/ssl/certs"
    chmod 700 "$BACKUP_DIR"
    
    log_success "Directory structure created"
}

#==============================================================================
# SSL CERTIFICATE GENERATION
#==============================================================================

generate_ssl_certificates() {
    if [[ "${CONFIG_VALUES[ENABLE_SSL]}" != "true" ]]; then
        return 0
    fi
    
    if [[ "${CONFIG_VALUES[SSL_TYPE]}" == "selfsigned" ]]; then
        log_step "Generating self-signed SSL certificates..."
        
        local ssl_dir="${CONFIG_DIR}/ssl/certs"
        
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$ssl_dir/key.pem" \
            -out "$ssl_dir/cert.pem" \
            -subj "/C=US/ST=State/L=City/O=Organization/CN=${CONFIG_VALUES[BASE_DOMAIN]}" \
            2>/dev/null
        
        chmod 600 "$ssl_dir/key.pem"
        chmod 644 "$ssl_dir/cert.pem"
        
        log_success "Self-signed SSL certificates generated"
    elif [[ "${CONFIG_VALUES[SSL_TYPE]}" == "custom" ]]; then
        log_step "Copying custom SSL certificates..."
        
        local ssl_dir="${CONFIG_DIR}/ssl/certs"
        
        cp "${CONFIG_VALUES[SSL_CERT_PATH]}" "$ssl_dir/cert.pem"
        cp "${CONFIG_VALUES[SSL_KEY_PATH]}" "$ssl_dir/key.pem"
        
        chmod 600 "$ssl_dir/key.pem"
        chmod 644 "$ssl_dir/cert.pem"
        
        log_success "Custom SSL certificates installed"
    fi
}

#==============================================================================
# SERVICE DEPLOYMENT
#==============================================================================

deploy_services() {
    log_step "Deploying services with Docker Compose..."
    
    cd "$PROJECT_ROOT"
    
    # Pull images
    log_info "Pulling Docker images..."
    docker-compose pull
    
    # Start services
    log_info "Starting services..."
    docker-compose up -d
    
    log_success "Services deployed"
}

#==============================================================================
# HEALTH CHECKS
#==============================================================================

wait_for_services() {
    log_step "Waiting for services to become healthy..."
    
    local max_wait=300  # 5 minutes
    local elapsed=0
    local interval=10
    
    local services=()
    [[ "${CONFIG_VALUES[INSTALL_POSTGRES]}" == "true" ]] && services+=("postgres")
    [[ "${CONFIG_VALUES[INSTALL_REDIS]}" == "true" ]] && services+=("redis")
    [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" == "true" ]] && services+=("ollama")
    [[ "${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}" == "true" ]] && services+=("open-webui")
    [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]] && services+=("n8n")
    
    while [[ $elapsed -lt $max_wait ]]; do
        local all_healthy=true
        
        for service in "${services[@]}"; do
            local health=$(docker inspect --format='{{.State.Health.Status}}' "${CONFIG_VALUES[COMPOSE_PROJECT_NAME]}_${service}" 2>/dev/null || echo "starting")
            
            if [[ "$health" != "healthy" ]]; then
                all_healthy=false
                log_info "Waiting for $service (status: $health)..."
                break
            fi
        done
        
        if $all_healthy; then
            log_success "All services are healthy!"
            return 0
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_warning "Some services may not be fully healthy yet"
    log_info "Check status with: docker-compose ps"
    return 1
}

#==============================================================================
# MODEL PRELOADING
#==============================================================================

preload_ollama_models() {
    if [[ "${CONFIG_VALUES[INSTALL_OLLAMA]}" != "true" ]] || [[ "${CONFIG_VALUES[PRELOAD_MODELS]}" != "true" ]]; then
        return 0
    fi
    
    log_step "Pre-loading Ollama models..."
    
    local models="${CONFIG_VALUES[OLLAMA_MODELS]}"
    IFS=',' read -ra MODEL_ARRAY <<< "$models"
    
    for model in "${MODEL_ARRAY[@]}"; do
        model=$(echo "$model" | xargs)  # Trim whitespace
        log_info "Pulling model: $model"
        
        docker exec "${CONFIG_VALUES[COMPOSE_PROJECT_NAME]}_ollama" ollama pull "$model" || {
            log_warning "Failed to pull model: $model"
        }
    done
    
    log_success "Model preloading complete"
}

#==============================================================================
# POST-DEPLOYMENT CONFIGURATION
#==============================================================================

post_deployment_config() {
    log_step "Running post-deployment configuration..."
    
    # Create default admin user if needed
    if [[ "${CONFIG_VALUES[AUTH_METHOD]}" == "local" ]] && [[ "${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}" == "true" ]]; then
        log_info "Creating admin user in Open WebUI..."
        
        # Wait a bit for Open WebUI to fully initialize
        sleep 10
        
        # Admin user creation would go here
        # (Open WebUI creates admin on first access, so this is informational)
    fi
    
    log_success "Post-deployment configuration complete"
}

#==============================================================================
# BACKUP CONFIGURATION SETUP
#==============================================================================

setup_backup_jobs() {
    if [[ "${CONFIG_VALUES[ENABLE_BACKUPS]}" != "true" ]]; then
        return 0
    fi
    
    log_step "Setting up backup jobs..."
    
    # Create backup script
    local backup_script="${PROJECT_ROOT}/scripts/backup.sh"
    
    cat > "$backup_script" << 'EOF'
#!/bin/bash
# Automated backup script
# Generated by AI Platform Setup

set -euo pipefail

BACKUP_DIR="${BACKUP_ROOT}/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup Docker volumes
docker run --rm \
    -v ${COMPOSE_PROJECT_NAME}_postgres_data:/source:ro \
    -v "$BACKUP_DIR":/backup \
    alpine tar czf /backup/postgres_data.tar.gz -C /source .

docker run --rm \
    -v ${COMPOSE_PROJECT_NAME}_ollama_data:/source:ro \
    -v "$BACKUP_DIR":/backup \
    alpine tar czf /backup/ollama_data.tar.gz -C /source .

# Backup configuration
tar czf "$BACKUP_DIR/config.tar.gz" -C "${PROJECT_ROOT}" config .env

# Cleanup old backups
find "${BACKUP_ROOT}" -type d -mtime +${BACKUP_RETENTION_DAYS} -exec rm -rf {} +

echo "Backup completed: $BACKUP_DIR"
EOF

    chmod +x "$backup_script"
    
    # Add cron job
    local cron_entry="${CONFIG_VALUES[BACKUP_SCHEDULE]} $backup_script"
    (crontab -l 2>/dev/null | grep -v "$backup_script" ; echo "$cron_entry") | crontab -
    
    log_success "Backup jobs configured"
}

#==============================================================================
# MAIN EXECUTION FUNCTION
#==============================================================================

main() {
    # Initialize logging FIRST
    create_log_directory
    initialize_logging
    
    log_info "Starting AI Platform Setup Wizard v2.0.0"
    log_info "Logging to: $LOG_FILE"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
    
    # Run wizard steps
    step_01_welcome
    step_02_services
    step_03_llm_providers
    step_04_proxy
    step_05_domains_ports
    step_06_authentication
    step_07_vector_db
    step_08_monitoring
    step_09_postgres
    step_10_redis
    step_11_resource_limits
    step_12_timezone
    step_13_gpu
    step_14_ssl
    step_15_backup
    step_16_logging
    step_17_security
    step_18_models
    step_19_network
    step_20_performance
    step_21_maintenance
    step_22_notifications
    step_23_integrations
    step_24_secrets
    step_25_custom_vars
    step_26_experimental
    
    # Review and confirm
    while ! step_27_review; do
        # Restart wizard if user declined
        log_info "Restarting configuration wizard..."
        continue
    done
    
    # Generate configuration files
    create_directory_structure
    generate_env_file
    generate_docker_compose
    generate_nginx_config
    generate_prometheus_config
    generate_litellm_config
    generate_ssl_certificates
    
    # Display summary
    display_configuration_summary
    
    # Deploy services
    if prompt_yes_no "Deploy services now?" "y"; then
        deploy_services
        wait_for_services
        preload_ollama_models
        post_deployment_config
        setup_backup_jobs
        
        cat << EOF

================================================================================
                      DEPLOYMENT COMPLETE!
================================================================================

Services are now running. Access them at:

EOF

        [[ "${CONFIG_VALUES[INSTALL_OPEN_WEBUI]}" == "true" ]] && echo "  • Open WebUI: ${CONFIG_VALUES[WEBUI_URL]}"
        [[ "${CONFIG_VALUES[INSTALL_N8N]}" == "true" ]] && echo "  • n8n: ${CONFIG_VALUES[N8N_URL]}"
        [[ "${CONFIG_VALUES[INSTALL_PORTAINER]}" == "true" ]] && echo "  • Portainer: https://localhost:${CONFIG_VALUES[PORTAINER_PORT]}"
        [[ "${CONFIG_VALUES[INSTALL_GRAFANA]}" == "true" ]] && echo "  • Grafana: http://localhost:${CONFIG_VALUES[GRAFANA_PORT]}"

        cat << EOF

Useful commands:
  • View logs:    docker-compose logs -f [service]
  • Restart:      docker-compose restart [service]
  • Stop all:     docker-compose down
  • Start all:    docker-compose up -d
  • Status:       docker-compose ps

Configuration saved to:
  • ${ENV_FILE}
  • ${DOCKER_COMPOSE_FILE}

================================================================================
EOF
    else
        cat << EOF

Configuration files generated. Deploy later with:
  cd $PROJECT_ROOT
  docker-compose up -d

EOF
    fi
    
    log_success "Setup completed successfully!"
}

#==============================================================================
# SCRIPT ENTRY POINT
#==============================================================================

# Trap errors
trap 'log_error "Script failed at line $LINENO"' ERR

# Run main function
main "$@"

#==============================================================================
# END OF PART 4/4
#==============================================================================
