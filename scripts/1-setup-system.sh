#!/bin/bash

#############################################################################
# Script 1: Initial Setup & System Validation
# Version: 73.0.0
# Description: Validates system and creates complete environment
# Last Updated: 2026-02-04
# FIX: Complete .env generation with all required variables
#############################################################################

set -euo pipefail

#############################################################################
# GLOBAL VARIABLES
#############################################################################

readonly SCRIPT_VERSION="73.0.0"
readonly SCRIPT_NAME="1-setup-system.sh"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Unicode symbols
readonly CHECK_MARK="✓"
readonly CROSS_MARK="✗"
readonly WARNING_SIGN="⚠"
readonly INFO_SIGN="ℹ"
readonly ROCKET="🚀"

# Paths
readonly INSTALL_DIR="/opt/ai-platform"
readonly ENV_FILE="${INSTALL_DIR}/.env"
readonly DATA_DIR="/var/lib/ai-platform"
readonly LOG_DIR="/var/log/ai-platform"
readonly CONFIG_DIR="${INSTALL_DIR}/config"
readonly COMPOSE_DIR="${INSTALL_DIR}/compose"
readonly BACKUP_DIR="/var/backups/ai-platform"

# System requirements
readonly MIN_RAM_GB=4
readonly MIN_CPU_CORES=2
readonly MIN_DISK_GB=20
readonly RECOMMENDED_RAM_GB=8
readonly RECOMMENDED_CPU_CORES=4
readonly RECOMMENDED_DISK_GB=50

#############################################################################
# LOGGING FUNCTIONS
#############################################################################

log_info() {
    echo -e "${BLUE}${INFO_SIGN}${NC} $*" | tee -a "${LOG_FILE:-/dev/null}"
}

log_success() {
    echo -e "${GREEN}${CHECK_MARK}${NC} $*" | tee -a "${LOG_FILE:-/dev/null}"
}

log_warn() {
    echo -e "${YELLOW}${WARNING_SIGN}${NC} $*" | tee -a "${LOG_FILE:-/dev/null}"
}

log_error() {
    echo -e "${RED}${CROSS_MARK}${NC} $*" | tee -a "${LOG_FILE:-/dev/null}"
}

#############################################################################
# UTILITY FUNCTIONS
#############################################################################

confirm_action() {
    local prompt="$1"
    local response
    
    while true; do
        read -r -p "$(echo -e "${YELLOW}${prompt}${NC} (yes/no): ")" response
        case "${response,,}" in
            yes|y) return 0 ;;
            no|n) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

check_command() {
    command -v "$1" >/dev/null 2>&1
}

#############################################################################
# SYSTEM VALIDATION
#############################################################################

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        return 1
    fi
    return 0
}

check_os() {
    log_info "Checking operating system..."
    
    if [ ! -f /etc/os-release ]; then
        log_error "Cannot determine OS version"
        return 1
    fi
    
    source /etc/os-release
    
    if [[ "${ID}" != "ubuntu" ]] && [[ "${ID}" != "debian" ]]; then
        log_warn "Unsupported OS: ${NAME}. Ubuntu/Debian recommended."
        if ! confirm_action "Continue anyway?"; then
            return 1
        fi
    fi
    
    log_success "OS: ${NAME} ${VERSION}"
    return 0
}

check_resources() {
    log_info "Checking system resources..."
    echo ""
    
    local warnings=0
    local critical_failures=0
    
    # CPU Check
    local cpu_cores
    cpu_cores=$(nproc)
    
    if [ "${cpu_cores}" -lt "${MIN_CPU_CORES}" ]; then
        log_error "CPU: ${cpu_cores} cores (minimum: ${MIN_CPU_CORES} cores required)"
        ((critical_failures++))
    elif [ "${cpu_cores}" -lt "${RECOMMENDED_CPU_CORES}" ]; then
        log_warn "CPU: ${cpu_cores} cores (recommended: ${RECOMMENDED_CPU_CORES} cores)"
        ((warnings++))
    else
        log_success "CPU: ${cpu_cores} cores"
    fi
    
    # RAM Check
    local total_ram_gb
    total_ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    
    if [ "${total_ram_gb}" -lt "${MIN_RAM_GB}" ]; then
        log_error "RAM: ${total_ram_gb} GB (minimum: ${MIN_RAM_GB} GB required)"
        ((critical_failures++))
    elif [ "${total_ram_gb}" -lt "${RECOMMENDED_RAM_GB}" ]; then
        log_warn "RAM: ${total_ram_gb} GB (recommended: ${RECOMMENDED_RAM_GB} GB)"
        ((warnings++))
    else
        log_success "RAM: ${total_ram_gb} GB"
    fi
    
    # Disk Check
    local available_disk_gb
    available_disk_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [ "${available_disk_gb}" -lt "${MIN_DISK_GB}" ]; then
        log_error "Disk: ${available_disk_gb} GB available (minimum: ${MIN_DISK_GB} GB required)"
        ((critical_failures++))
    elif [ "${available_disk_gb}" -lt "${RECOMMENDED_DISK_GB}" ]; then
        log_warn "Disk: ${available_disk_gb} GB available (recommended: ${RECOMMENDED_DISK_GB} GB)"
        ((warnings++))
    else
        log_success "Disk: ${available_disk_gb} GB available"
    fi
    
    echo ""
    log_info "Resource Check Summary:"
    
    if [ "${critical_failures}" -gt 0 ]; then
        log_error "Critical failures: ${critical_failures}"
        log_error "System does not meet minimum requirements"
        return 1
    fi
    
    if [ "${warnings}" -gt 0 ]; then
        log_warn "Warnings: ${warnings}"
        log_warn "System meets minimum but not recommended requirements"
        
        if ! confirm_action "Continue with current system specifications?"; then
            return 1
        fi
    else
        log_success "All resource checks passed"
    fi
    
    return 0
}

#############################################################################
# PACKAGE INSTALLATION
#############################################################################

install_docker() {
    if check_command docker; then
        log_success "Docker already installed: $(docker --version)"
        return 0
    fi
    
    log_info "Installing Docker..."
    
    # Install dependencies
    apt-get update -qq
    apt-get install -y -qq \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker GPG key
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt-get update -qq
    apt-get install -y -qq \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
    
    # Start Docker
    systemctl enable docker
    systemctl start docker
    
    # Add current user to docker group
    if [ -n "${SUDO_USER:-}" ]; then
        usermod -aG docker "${SUDO_USER}"
        log_info "Added ${SUDO_USER} to docker group (logout/login required)"
    fi
    
    log_success "Docker installed: $(docker --version)"
    return 0
}

install_required_packages() {
    log_info "Installing required packages..."
    
    apt-get update -qq
    
    local packages=(
        "curl"
        "wget"
        "git"
        "jq"
        "openssl"
        "net-tools"
        "htop"
        "vim"
        "unzip"
        "sudo"
    )
    
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  ${package} "; then
            apt-get install -y -qq "${package}"
        fi
    done
    
    log_success "Required packages installed"
    return 0
}

#############################################################################
# DIRECTORY SETUP
#############################################################################

setup_directories() {
    log_info "Setting up directory structure..."
    
    local directories=(
        "${INSTALL_DIR}"
        "${DATA_DIR}"
        "${LOG_DIR}"
        "${CONFIG_DIR}"
        "${COMPOSE_DIR}"
        "${BACKUP_DIR}"
        "${DATA_DIR}/postgres"
        "${DATA_DIR}/redis"
        "${DATA_DIR}/ollama"
        "${DATA_DIR}/minio"
        "${DATA_DIR}/qdrant"
        "${DATA_DIR}/chromadb"
        "${DATA_DIR}/weaviate"
        "${DATA_DIR}/n8n"
        "${DATA_DIR}/prometheus"
        "${DATA_DIR}/grafana"
        "${DATA_DIR}/loki"
    )
    
    for dir in "${directories[@]}"; do
        if [ ! -d "${dir}" ]; then
            mkdir -p "${dir}"
            chmod 755 "${dir}"
        fi
    done
    
    log_success "Directory structure created"
    return 0
}

#############################################################################
# ENVIRONMENT CONFIGURATION - COMPLETE VERSION
#############################################################################

generate_environment_file() {
    log_info "Generating environment configuration..."
    
    # Get system information
    local host_ip
    local hostname_val
    local domain_val
    
    host_ip=$(hostname -I | awk '{print $1}')
    hostname_val=$(hostname)
    domain_val="${hostname_val}.local"
    
    # Generate secure passwords
    local postgres_password
    local redis_password
    local litellm_key
    local webui_key
    local grafana_password
    local minio_root_password
    local n8n_encryption_key
    
    postgres_password=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
    redis_password=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
    litellm_key=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
    webui_key=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
    grafana_password=$(openssl rand -base64 16 | tr -d '/+=' | head -c 16)
    minio_root_password=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
    n8n_encryption_key=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
    
    # Create complete .env file
    cat > "${ENV_FILE}" << ENV_EOF
#############################################################################
# AI Platform Configuration
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# Version: ${SCRIPT_VERSION}
#############################################################################

#############################################################################
# SYSTEM CONFIGURATION
#############################################################################
HOST_IP=${host_ip}
HOSTNAME=${hostname_val}
DOMAIN=${domain_val}
TIMEZONE=UTC
ENVIRONMENT=production

#############################################################################
# NETWORK CONFIGURATION
#############################################################################
SUBNET=172.28.0.0/16
GATEWAY=172.28.0.1

# Service Ports (will be dynamically allocated by Script 2)
HTTP_PORT=80
HTTPS_PORT=443
OPEN_WEBUI_PORT=3000
LITELLM_PORT=8000
OLLAMA_PORT=11434
POSTGRES_PORT=5432
REDIS_PORT=6379
GRAFANA_PORT=3500
PROMETHEUS_PORT=9090
MINIO_PORT=9000
MINIO_CONSOLE_PORT=9001
N8N_PORT=5678
QDRANT_PORT=6333
CHROMADB_PORT=8900
WEAVIATE_PORT=8080
ANYTHINGLLM_PORT=3001
DIFY_API_PORT=5001
DIFY_WEB_PORT=3002
LOKI_PORT=3100

#############################################################################
# DATABASE CONFIGURATION
#############################################################################
POSTGRES_USER=aiplatform
POSTGRES_PASSWORD=${postgres_password}
POSTGRES_DB=aiplatform
POSTGRES_HOST=postgres
POSTGRES_PORT=5432

# Dify Database
DIFY_DB_USER=dify
DIFY_DB_PASSWORD=${postgres_password}
DIFY_DB_NAME=dify
DIFY_DB_HOST=dify-db
DIFY_DB_PORT=5432

#############################################################################
# REDIS CONFIGURATION
#############################################################################
REDIS_PASSWORD=${redis_password}
REDIS_HOST=redis
REDIS_PORT=6379

# Dify Redis
DIFY_REDIS_HOST=dify-redis
DIFY_REDIS_PORT=6379
DIFY_REDIS_PASSWORD=${redis_password}

#############################################################################
# OLLAMA CONFIGURATION
#############################################################################
OLLAMA_HOST=ollama
OLLAMA_PORT=11434
OLLAMA_API_BASE=http://ollama:11434
OLLAMA_MODELS=llama3.2:1b,llama3.2:3b
OLLAMA_NUM_PARALLEL=4
OLLAMA_MAX_LOADED_MODELS=2

#############################################################################
# LITELLM CONFIGURATION
#############################################################################
LITELLM_MASTER_KEY=${litellm_key}
LITELLM_PORT=8000
LITELLM_API_BASE=http://litellm:8000
LITELLM_ROUTER_MODE=simple-shuffle
LITELLM_ENABLE_RATE_LIMIT=false
LITELLM_RATE_LIMIT_RPM=100

# External LLM APIs (to be configured in Script 2)
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
GOOGLE_API_KEY=
GROQ_API_KEY=
DEEPSEEK_API_KEY=

#############################################################################
# OPEN WEBUI CONFIGURATION
#############################################################################
WEBUI_SECRET_KEY=${webui_key}
WEBUI_PORT=3000
WEBUI_NAME=AI Platform
WEBUI_URL=http://${host_ip}:3000
ENABLE_RAG_WEB_SEARCH=true
ENABLE_IMAGE_GENERATION=false
ENABLE_COMMUNITY_SHARING=false

#############################################################################
# ANYTHINGLLM CONFIGURATION
#############################################################################
ANYTHINGLLM_PORT=3001
STORAGE_DIR=/app/server/storage
SERVER_PORT=3001

#############################################################################
# DIFY CONFIGURATION
#############################################################################
DIFY_API_PORT=5001
DIFY_WEB_PORT=3002
DIFY_SECRET_KEY=${webui_key}
DIFY_SANDBOX_API_KEY=${litellm_key}
DIFY_CODE_EXECUTION_ENDPOINT=http://dify-sandbox:8194
DIFY_CODE_EXECUTION_API_KEY=${litellm_key}
DIFY_LOG_LEVEL=INFO

#############################################################################
# VECTOR DATABASE CONFIGURATION
#############################################################################

# Weaviate
WEAVIATE_PORT=8080
WEAVIATE_GRPC_PORT=50051
WEAVIATE_API_KEY=${litellm_key}
QUERY_DEFAULTS_LIMIT=25
AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED=true
PERSISTENCE_DATA_PATH=/var/lib/weaviate
CLUSTER_HOSTNAME=weaviate-node

# Qdrant
QDRANT_PORT=6333
QDRANT_GRPC_PORT=6334
QDRANT_API_KEY=${litellm_key}

# ChromaDB
CHROMADB_PORT=8900
CHROMADB_AUTH_TOKEN=${litellm_key}

#############################################################################
# MINIO CONFIGURATION
#############################################################################
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=${minio_root_password}
MINIO_PORT=9000
MINIO_CONSOLE_PORT=9001
MINIO_BUCKET_NAME=ai-platform
MINIO_REGION=us-east-1

#############################################################################
# N8N CONFIGURATION
#############################################################################
N8N_PORT=5678
N8N_ENCRYPTION_KEY=${n8n_encryption_key}
N8N_HOST=n8n
N8N_PROTOCOL=http
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=${grafana_password}

#############################################################################
# MONITORING CONFIGURATION
#############################################################################

# Grafana
GRAFANA_PORT=3500
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=${grafana_password}
GRAFANA_INSTALL_PLUGINS=

# Prometheus
PROMETHEUS_PORT=9090
PROMETHEUS_RETENTION_TIME=15d
PROMETHEUS_STORAGE_PATH=/prometheus

# Loki
LOKI_PORT=3100

#############################################################################
# TAILSCALE CONFIGURATION
#############################################################################
ENABLE_TAILSCALE=false
TAILSCALE_AUTH_KEY=
TAILSCALE_HOSTNAME=${hostname_val}

#############################################################################
# BACKUP CONFIGURATION
#############################################################################
BACKUP_ENABLED=true
BACKUP_RETENTION_DAYS=7
BACKUP_DIR=${BACKUP_DIR}

#############################################################################
# SECURITY CONFIGURATION
#############################################################################
SSL_ENABLED=false
SSL_CERT_PATH=
SSL_KEY_PATH=

#############################################################################
# FEATURE FLAGS
#############################################################################
ENABLE_METRICS=true
ENABLE_LOGGING=true
ENABLE_TRACING=false
ENABLE_DEBUG=false

ENV_EOF

    chmod 600 "${ENV_FILE}"
    
    log_success "Environment file created: ${ENV_FILE}"
    return 0
}

#############################################################################
# MAIN EXECUTION
#############################################################################

main() {
    clear
    
    cat << 'BANNER_EOF'
╔════════════════════════════════════════════════════════════════════╗
║                                                                    ║
║              AI Platform - Initial Setup                           ║
║                      Version 73.0.0                                ║
║                                                                    ║
║    System Validation & Environment Preparation                     ║
║                                                                    ║
╚════════════════════════════════════════════════════════════════════╝
BANNER_EOF
    echo ""
    
    # Setup logging
    mkdir -p "${LOG_DIR}"
    LOG_FILE="${LOG_DIR}/setup-$(date +%Y%m%d_%H%M%S).log"
    
    log_info "Starting system setup..."
    echo ""
    
    # System checks
    if ! check_root; then
        exit 1
    fi
    
    if ! check_os; then
        exit 1
    fi
    
    if ! check_resources; then
        exit 1
    fi
    
    echo ""
    log_info "Installing dependencies..."
    
    if ! install_required_packages; then
        log_error "Package installation failed"
        exit 1
    fi
    
    if ! install_docker; then
        log_error "Docker installation failed"
        exit 1
    fi
    
    echo ""
    log_info "Setting up environment..."
    
    if ! setup_directories; then
        log_error "Directory setup failed"
        exit 1
    fi
    
    if ! generate_environment_file; then
        log_error "Environment file generation failed"
        exit 1
    fi
    
    echo ""
    log_success "System setup completed successfully!"
    echo ""
    log_info "Next steps:"
    log_info "  1. Review configuration: ${ENV_FILE}"
    log_info "  2. Run deployment: sudo ./2-deploy-services.sh"
    echo ""
    log_info "Log file: ${LOG_FILE}"
    echo ""
    
    return 0
}

#############################################################################
# SCRIPT EXECUTION
#############################################################################

main "$@"
exit $?
