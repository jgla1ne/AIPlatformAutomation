#!/bin/bash
set -euo pipefail

# ============================================================================
# AI Platform System Setup - Script 1
# Handles: Dependencies, directories, credentials, configuration
# ============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Determine paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="/mnt/data"
LOG_DIR="$DATA_DIR/logs"
BACKUP_DIR="$DATA_DIR/backups"
CONFIG_FILE="$BASE_DIR/.env"
STATE_FILE="$BASE_DIR/.setup_state"

# ============================================================================
# Signal Handling
# ============================================================================

cleanup() {
    local exit_code=$?
    echo ""
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}✗ Setup interrupted or failed${NC}"
        echo "State saved to: $STATE_FILE"
        echo "Logs available at: $LOG_DIR/setup.log"
    fi
    exit $exit_code
}

trap cleanup EXIT
trap 'echo -e "\n${YELLOW}⚠ Received interrupt signal${NC}"; exit 130' INT TERM

# ============================================================================
# Utility Functions
# ============================================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/setup.log"
    
    case $level in
        ERROR)   echo -e "${RED}✗ $message${NC}" ;;
        SUCCESS) echo -e "${GREEN}✓ $message${NC}" ;;
        WARN)    echo -e "${YELLOW}⚠ $message${NC}" ;;
        INFO)    echo -e "${CYAN}ℹ $message${NC}" ;;
        *)       echo "$message" ;;
    esac
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log ERROR "This script must be run as root"
        exit 1
    fi
}

generate_random() {
    local length=${1:-32}
    openssl rand -base64 $length | tr -d "=+/" | cut -c1-$length
}

detect_public_ip() {
    local ip=""
    # Try multiple services
    ip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null) || \
    ip=$(curl -s --connect-timeout 5 icanhazip.com 2>/dev/null) || \
    ip=$(curl -s --connect-timeout 5 api.ipify.org 2>/dev/null) || \
    ip="unknown"
    echo "$ip"
}

prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local value=""
    
    read -p "$prompt [$default]: " value
    value=${value:-$default}
    
    # Export to environment
    export "$var_name=$value"
    echo "$var_name=\"$value\"" >> "$CONFIG_FILE"
}

prompt_secret() {
    local prompt="$1"
    local var_name="$2"
    local value=""
    
    read -s -p "$prompt: " value
    echo ""
    
    if [ -z "$value" ]; then
        value=$(generate_random 32)
        log WARN "No value provided, generated: ${value:0:8}..."
    fi
    
    export "$var_name=$value"
    echo "$var_name=\"$value\"" >> "$CONFIG_FILE"
}

wait_for_port() {
    local port=$1
    local service=${2:-"service"}
    local max_wait=30
    local count=0
    
    log INFO "Waiting for $service on port $port..."
    while [ $count -lt $max_wait ]; do
        if timeout 2 bash -c "cat < /dev/null > /dev/tcp/localhost/$port" 2>/dev/null; then
            log SUCCESS "$service is responding on port $port"
            return 0
        fi
        sleep 2
        ((count++))
    done
    
    log ERROR "$service did not start on port $port within ${max_wait}s"
    return 1
}

# ============================================================================
# Main Setup
# ============================================================================

main() {
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║         AI Platform System Setup - Script 1                ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    check_root
    
    # Create initial directories
    log INFO "Creating directory structure..."
    mkdir -p "$BASE_DIR"/{n8n,flowise,litellm,langfuse,openclaw}
    mkdir -p "$DATA_DIR"/{postgresql,n8n,flowise,nginx/logs,nginx/ssl,backups,uploads,qdrant}
    mkdir -p "$LOG_DIR"/{n8n,flowise,litellm,langfuse,nginx,openclaw,setup}
    
    # Initialize config file
    cat > "$CONFIG_FILE" <<EOF
# AI Platform Configuration
# Generated: $(date)
# Base Directory: $BASE_DIR
# Data Directory: $DATA_DIR

# ============================================================================
# System Configuration
# ============================================================================
EOF
    
    log SUCCESS "Directory structure created"
    
    # ========================================================================
    # Network Detection
    # ========================================================================
    
    echo ""
    echo -e "${BLUE}═══ Network Configuration ═══${NC}"
    
    PUBLIC_IP=$(detect_public_ip)
    log INFO "Detected public IP: $PUBLIC_IP"
    echo "PUBLIC_IP=\"$PUBLIC_IP\"" >> "$CONFIG_FILE"
    
    # ========================================================================
    # Tailscale Configuration
    # ========================================================================
    
    echo ""
    echo -e "${BLUE}═══ Tailscale Configuration ═══${NC}"
    
    if ! command -v tailscale &> /dev/null; then
        log INFO "Installing Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh
        
        # Configure for port 8443
        mkdir -p /etc/default
        cat > /etc/default/tailscaled <<EOF
FLAGS="--port 8443"
EOF
        systemctl restart tailscaled
        log SUCCESS "Tailscale installed and configured for port 8443"
    else
        log INFO "Tailscale already installed"
    fi
    
    # Check if connected
    if ! tailscale status &>/dev/null; then
        log WARN "Tailscale not connected. Please authenticate:"
        tailscale up --accept-routes --accept-dns=false
    fi
    
    # Get Tailscale details
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
    TAILSCALE_HOSTNAME=$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//' || echo "")
    
    if [ -z "$TAILSCALE_IP" ]; then
        log ERROR "Tailscale not properly connected"
        exit 1
    fi
    
    log SUCCESS "Tailscale IP: $TAILSCALE_IP"
    log SUCCESS "Tailscale Hostname: $TAILSCALE_HOSTNAME"
    
    cat >> "$CONFIG_FILE" <<EOF
TAILSCALE_IP="$TAILSCALE_IP"
TAILSCALE_HOSTNAME="$TAILSCALE_HOSTNAME"
PLATFORM_URL="https://${TAILSCALE_HOSTNAME}:8443"

EOF
    
    # ========================================================================
    # Port Configuration
    # ========================================================================
    
    echo ""
    echo -e "${BLUE}═══ Port Configuration ═══${NC}"
    
    cat >> "$CONFIG_FILE" <<EOF
# ============================================================================
# Service Ports
# ============================================================================
EOF
    
    prompt_with_default "Nginx HTTPS port" "8443" "NGINX_HTTPS_PORT"
    prompt_with_default "N8N port" "5678" "N8N_PORT"
    prompt_with_default "Flowise port" "3000" "FLOWISE_PORT"
    prompt_with_default "LiteLLM port" "4000" "LITELLM_PORT"
    prompt_with_default "Langfuse port" "3001" "LANGFUSE_PORT"
    prompt_with_default "Qdrant port" "6333" "QDRANT_PORT"
    prompt_with_default "PostgreSQL port" "5432" "POSTGRES_PORT"
    
    echo "" >> "$CONFIG_FILE"
    
    # ========================================================================
    # Database Configuration
    # ========================================================================
    
    echo ""
    echo -e "${BLUE}═══ Database Configuration ═══${NC}"
    
    cat >> "$CONFIG_FILE" <<EOF
# ============================================================================
# Database Configuration
# ============================================================================
POSTGRES_VERSION="15"
POSTGRES_DATA_DIR="$DATA_DIR/postgresql/15/main"

EOF
    
    log INFO "Generating database passwords..."
    
    N8N_DB_PASSWORD=$(generate_random 32)
    FLOWISE_DB_PASSWORD=$(generate_random 32)
    LITELLM_DB_PASSWORD=$(generate_random 32)
    LANGFUSE_DB_PASSWORD=$(generate_random 32)
    
    cat >> "$CONFIG_FILE" <<EOF
N8N_DB_PASSWORD="$N8N_DB_PASSWORD"
FLOWISE_DB_PASSWORD="$FLOWISE_DB_PASSWORD"
LITELLM_DB_PASSWORD="$LITELLM_DB_PASSWORD"
LANGFUSE_DB_PASSWORD="$LANGFUSE_DB_PASSWORD"

EOF
    
    log SUCCESS "Database passwords generated"
    
    # ========================================================================
    # N8N Configuration
    # ========================================================================
    
    echo ""
    echo -e "${BLUE}═══ N8N Configuration ═══${NC}"
    
    cat >> "$CONFIG_FILE" <<EOF
# ============================================================================
# N8N Configuration
# ============================================================================
N8N_PROTOCOL="https"
N8N_HOST="0.0.0.0"
N8N_USER_FOLDER="$DATA_DIR/n8n"
N8N_BINARY_DATA_STORAGE_PATH="$DATA_DIR/n8n/binary-data"
WEBHOOK_URL="https://${TAILSCALE_HOSTNAME}:8443/n8n"
EOF
    
    N8N_ENCRYPTION_KEY=$(generate_random 32)
    echo "N8N_ENCRYPTION_KEY=\"$N8N_ENCRYPTION_KEY\"" >> "$CONFIG_FILE"
    
    echo ""
    read -p "Create N8N admin user? [Y/n]: " create_n8n_admin
    if [[ ! "$create_n8n_admin" =~ ^[Nn]$ ]]; then
        prompt_with_default "N8N admin email" "admin@localhost" "N8N_ADMIN_EMAIL"
        prompt_secret "N8N admin password" "N8N_ADMIN_PASSWORD"
    fi
    
    echo "" >> "$CONFIG_FILE"
    log SUCCESS "N8N configuration complete"
    
    # ========================================================================
    # Flowise Configuration
    # ========================================================================
    
    echo ""
    echo -e "${BLUE}═══ Flowise Configuration ═══${NC}"
    
    cat >> "$CONFIG_FILE" <<EOF
# ============================================================================
# Flowise Configuration
# ============================================================================
FLOWISE_USERNAME="admin"
FLOWISE_STORAGE_PATH="$DATA_DIR/flowise"
APIKEY_PATH="$DATA_DIR/flowise/api-keys"
LOG_PATH="$LOG_DIR/flowise"
SECRETKEY_PATH="$DATA_DIR/flowise/secrets"
BLOB_STORAGE_PATH="$DATA_DIR/flowise/storage"
EOF
    
    prompt_secret "Flowise admin password" "FLOWISE_PASSWORD"
    
    echo "" >> "$CONFIG_FILE"
    log SUCCESS "Flowise configuration complete"
    
    # ========================================================================
    # LiteLLM Configuration
    # ========================================================================
    
    echo ""
    echo -e "${BLUE}═══ LiteLLM Configuration ═══${NC}"
    
    cat >> "$CONFIG_FILE" <<EOF
# ============================================================================
# LiteLLM Configuration
# ============================================================================
EOF
    
    LITELLM_MASTER_KEY=$(generate_random 32)
    echo "LITELLM_MASTER_KEY=\"$LITELLM_MASTER_KEY\"" >> "$CONFIG_FILE"
    
    echo ""
    echo "Configure LLM providers:"
    read -p "Enable OpenAI? [Y/n]: " enable_openai
    if [[ ! "$enable_openai" =~ ^[Nn]$ ]]; then
        prompt_secret "OpenAI API Key" "OPENAI_API_KEY"
    fi
    
    read -p "Enable Azure OpenAI? [y/N]: " enable_azure
    if [[ "$enable_azure" =~ ^[Yy]$ ]]; then
        prompt_with_default "Azure OpenAI Endpoint" "" "AZURE_API_BASE"
        prompt_secret "Azure OpenAI API Key" "AZURE_API_KEY"
        prompt_with_default "Azure API Version" "2024-02-15-preview" "AZURE_API_VERSION"
    fi
    
    read -p "Enable Anthropic? [y/N]: " enable_anthropic
    if [[ "$enable_anthropic" =~ ^[Yy]$ ]]; then
        prompt_secret "Anthropic API Key" "ANTHROPIC_API_KEY"
    fi
    
    echo "" >> "$CONFIG_FILE"
    log SUCCESS "LiteLLM configuration complete"
    
    # ========================================================================
    # Langfuse Configuration
    # ========================================================================
    
    echo ""
    echo -e "${BLUE}═══ Langfuse Configuration ═══${NC}"
    
    cat >> "$CONFIG_FILE" <<EOF
# ============================================================================
# Langfuse Configuration
# ============================================================================
NEXTAUTH_URL="https://${TAILSCALE_HOSTNAME}:8443/langfuse"
TELEMETRY_ENABLED="false"
EOF
    
    LANGFUSE_NEXTAUTH_SECRET=$(generate_random 32)
    LANGFUSE_SALT=$(generate_random 32)
    LANGFUSE_INIT_PROJECT_SECRET=$(generate_random 32)
    LANGFUSE_INIT_PROJECT_PUBLIC=$(generate_random 16)
    
    cat >> "$CONFIG_FILE" <<EOF
NEXTAUTH_SECRET="$LANGFUSE_NEXTAUTH_SECRET"
SALT="$LANGFUSE_SALT"
LANGFUSE_INIT_PROJECT_ID="default"
LANGFUSE_INIT_PROJECT_SECRET_KEY="$LANGFUSE_INIT_PROJECT_SECRET"
LANGFUSE_INIT_PROJECT_PUBLIC_KEY="$LANGFUSE_INIT_PROJECT_PUBLIC"

EOF
    
    log SUCCESS "Langfuse configuration complete"
    
    # ========================================================================
    # Qdrant Vector Database Configuration (for OpenClaw)
    # ========================================================================
    
    echo ""
    echo -e "${BLUE}═══ Qdrant Vector Database Configuration ═══${NC}"
    
    cat >> "$CONFIG_FILE" <<EOF
# ============================================================================
# Qdrant Configuration (Vector Database)
# ============================================================================
QDRANT_HOST="localhost"
QDRANT_DATA_DIR="$DATA_DIR/qdrant"
QDRANT_GRPC_PORT="6334"
EOF
    
    QDRANT_API_KEY=$(generate_random 32)
    echo "QDRANT_API_KEY=\"$QDRANT_API_KEY\"" >> "$CONFIG_FILE"
    echo "" >> "$CONFIG_FILE"
    
    log SUCCESS "Qdrant configuration complete"
    
    # ========================================================================
    # OpenClaw Configuration (if enabled)
    # ========================================================================
    
    echo ""
    read -p "Enable OpenClaw integration? [y/N]: " enable_openclaw
    if [[ "$enable_openclaw" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${BLUE}═══ OpenClaw Configuration ═══${NC}"
        
        cat >> "$CONFIG_FILE" <<EOF
# ============================================================================
# OpenClaw Configuration
# ============================================================================
OPENCLAW_ENABLED="true"
OPENCLAW_DATA_DIR="$DATA_DIR/openclaw"
OPENCLAW_VECTOR_DB="qdrant"
OPENCLAW_VECTOR_DB_URL="http://localhost:${QDRANT_PORT:-6333}"
EOF
        
        prompt_with_default "OpenClaw API port" "8080" "OPENCLAW_API_PORT"
        
        OPENCLAW_API_KEY=$(generate_random 32)
        echo "OPENCLAW_API_KEY=\"$OPENCLAW_API_KEY\"" >> "$CONFIG_FILE"
        echo "" >> "$CONFIG_FILE"
        
        log SUCCESS "OpenClaw configuration complete"
    else
        echo "OPENCLAW_ENABLED=\"false\"" >> "$CONFIG_FILE"
        echo "" >> "$CONFIG_FILE"
    fi
    
    # ========================================================================
    # System Dependencies Installation
    # ========================================================================
    
    echo ""
    echo -e "${BLUE}═══ Installing System Dependencies ═══${NC}"
    
    log INFO "Updating package lists..."
    apt-get update -qq
    
    log INFO "Installing base packages..."
    apt-get install -y -qq \
        curl \
        wget \
        git \
        jq \
        openssl \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common \
        build-essential \
        python3 \
        python3-pip \
        python3-venv
    
    log SUCCESS "Base packages installed"
    
    # ========================================================================
    # Node.js Installation
    # ========================================================================
    
    log INFO "Installing Node.js 20..."
    if ! command -v node &> /dev/null || ! node --version | grep -q "v20"; then
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y nodejs
        
        # Verify installation
        if ! node --version | grep -q "v20"; then
            log ERROR "Node.js 20 installation failed"
            exit 1
        fi
    fi
    
    NODE_VERSION=$(node --version)
    NPM_VERSION=$(npm --version)
    log SUCCESS "Node.js $NODE_VERSION and npm $NPM_VERSION installed"
    
    # ========================================================================
    # PostgreSQL Installation
    # ========================================================================
    
    log INFO "Installing PostgreSQL 15..."
    if ! command -v psql &> /dev/null; then
        # Add PostgreSQL repo
        curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
        
        apt-get update -qq
        apt-get install -y postgresql-15 postgresql-contrib-15
        
        log SUCCESS "PostgreSQL 15 installed"
    else
        log INFO "PostgreSQL already installed"
    fi
    
    # Configure PostgreSQL data directory
    systemctl stop postgresql
    
    # Create data directory with proper permissions
    mkdir -p "$DATA_DIR/postgresql/15/main"
    chown -R postgres:postgres "$DATA_DIR/postgresql"
    chmod 700 "$DATA_DIR/postgresql/15/main"
    
    # Initialize if empty
    if [ ! -f "$DATA_DIR/postgresql/15/main/PG_VERSION" ]; then
        log INFO "Initializing PostgreSQL data directory..."
        sudo -u postgres /usr/lib/postgresql/15/bin/initdb -D "$DATA_DIR/postgresql/15/main"
    fi
    
    # Update PostgreSQL configuration
    sed -i "s|data_directory = '.*'|data_directory = '$DATA_DIR/postgresql/15/main'|" \
        /etc/postgresql/15/main/postgresql.conf
    
    # Configure PostgreSQL for better performance
    cat >> /etc/postgresql/15/main/postgresql.conf <<EOF

# AI Platform Optimizations
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
work_mem = 4MB
min_wal_size = 1GB
max_wal_size = 4GB
max_connections = 200
EOF
    
    systemctl start postgresql
    systemctl enable postgresql
    
    wait_for_port 5432 "PostgreSQL"
    
    log SUCCESS "PostgreSQL configured with data at $DATA_DIR/postgresql"
    
    # ========================================================================
    # Create Databases and Users
    # ========================================================================
    
    log INFO "Creating databases and users..."
    
    sudo -u postgres psql <<EOF
-- N8N Database
DROP DATABASE IF EXISTS n8n;
DROP USER IF EXISTS n8n;
CREATE USER n8n WITH PASSWORD '$N8N_DB_PASSWORD';
CREATE DATABASE n8n OWNER n8n;
GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n;

-- Flowise Database
DROP DATABASE IF EXISTS flowise;
DROP USER IF EXISTS flowise;
CREATE USER flowise WITH PASSWORD '$FLOWISE_DB_PASSWORD';
CREATE DATABASE flowise OWNER flowise;
GRANT ALL PRIVILEGES ON DATABASE flowise TO flowise;

-- LiteLLM Database
DROP DATABASE IF EXISTS litellm;
DROP USER IF EXISTS litellm;
CREATE USER litellm WITH PASSWORD '$LITELLM_DB_PASSWORD';
CREATE DATABASE litellm OWNER litellm;
GRANT ALL PRIVILEGES ON DATABASE litellm TO litellm;

-- Langfuse Database
DROP DATABASE IF EXISTS langfuse;
DROP USER IF EXISTS langfuse;
CREATE USER langfuse WITH PASSWORD '$LANGFUSE_DB_PASSWORD';
CREATE DATABASE langfuse OWNER langfuse;
GRANT ALL PRIVILEGES ON DATABASE langfuse TO langfuse;
EOF
    
    log SUCCESS "Databases and users created"
    
    # ========================================================================
    # Nginx Installation
    # ========================================================================
    
    log INFO "Installing Nginx..."
    if ! command -v nginx &> /dev/null; then
        apt-get install -y nginx
    fi
    
    systemctl enable nginx
    log SUCCESS "Nginx installed"
    
    # ========================================================================
    # Docker Installation (for Qdrant)
    # ========================================================================
    
    if [[ "${OPENCLAW_ENABLED:-false}" == "true" ]] || [[ "${QDRANT_PORT:-}" ]]; then
        log INFO "Installing Docker for Qdrant..."
        
        if ! command -v docker &> /dev/null; then
            curl -fsSL https://get.docker.com -o get-docker.sh
            sh get-docker.sh
            rm get-docker.sh
            
            systemctl enable docker
            systemctl start docker
            
            log SUCCESS "Docker installed"
        else
            log INFO "Docker already installed"
        fi
        
        # Pull Qdrant image
        log INFO "Pulling Qdrant Docker image..."
        docker pull qdrant/qdrant:latest
        
        log SUCCESS "Qdrant image ready"
    fi
    
    # ========================================================================
    # Final Directory Permissions
    # ========================================================================
    
    log INFO "Setting directory permissions..."
    
    chown -R root:root "$BASE_DIR"
    chown -R root:root "$DATA_DIR"
    chmod -R 755 "$BASE_DIR"
    chmod -R 755 "$DATA_DIR"
    chmod 600 "$CONFIG_FILE"
    
    # PostgreSQL data needs postgres ownership
    chown -R postgres:postgres "$DATA_DIR/postgresql"
    chmod 700 "$DATA_DIR/postgresql/15/main"
    
    log SUCCESS "Permissions configured"
    
    # ========================================================================
    # Health Checks
    # ========================================================================
    
    echo ""
    echo -e "${BLUE}═══ Running Health Checks ═══${NC}"
    
    # Check Node.js
    if command -v node &> /dev/null && node --version | grep -q "v20"; then
        log SUCCESS "Node.js 20: OK"
    else
        log ERROR "Node.js 20: FAILED"
    fi
    
    # Check npm
    if command -v npm &> /dev/null; then
        log SUCCESS "npm: OK"
    else
        log ERROR "npm: FAILED"
    fi
    
    # Check PostgreSQL
    if systemctl is-active --quiet postgresql && pg_isready -q; then
        log SUCCESS "PostgreSQL: OK"
    else
        log ERROR "PostgreSQL: FAILED"
    fi
    
    # Check Nginx
    if command -v nginx &> /dev/null && nginx -t &>/dev/null; then
        log SUCCESS "Nginx: OK"
    else
        log ERROR "Nginx: FAILED"
    fi
    
    # Check Tailscale
    if tailscale status &>/dev/null; then
        log SUCCESS "Tailscale: OK (${TAILSCALE_IP})"
    else
        log ERROR "Tailscale: FAILED"
    fi
    
    # Check Docker (if needed)
    if [[ "${OPENCLAW_ENABLED:-false}" == "true" ]]; then
        if command -v docker &> /dev/null && docker ps &>/dev/null; then
            log SUCCESS "Docker: OK"
        else
            log ERROR "Docker: FAILED"
        fi
    fi
    
    # Check database connectivity
    for db in n8n flowise litellm langfuse; do
        if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$db"; then
            log SUCCESS "Database '$db': OK"
        else
            log ERROR "Database '$db': FAILED"
        fi
    done
    
    # ========================================================================
    # Save State
    # ========================================================================
    
    cat > "$STATE_FILE" <<EOF
SETUP_COMPLETE=true
SETUP_DATE=$(date -Iseconds)
SCRIPT_1_COMPLETE=true
NODE_VERSION=$NODE_VERSION
POSTGRES_VERSION=15
TAILSCALE_IP=$TAILSCALE_IP
TAILSCALE_HOSTNAME=$TAILSCALE_HOSTNAME
EOF
    
    # ========================================================================
    # Summary
    # ========================================================================
    
    echo ""
    echo -e "${GREEN}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              Setup Complete - Summary                      ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo -e "${CYAN}System Information:${NC}"
    echo "  • Base Directory:    $BASE_DIR"
    echo "  • Data Directory:    $DATA_DIR"
    echo "  • Public IP:         $PUBLIC_IP"
    echo "  • Tailscale IP:      $TAILSCALE_IP"
    echo "  • Tailscale Host:    $TAILSCALE_HOSTNAME"
    echo "  • Platform URL:      https://${TAILSCALE_HOSTNAME}:8443"
    echo ""
    echo -e "${CYAN}Installed Components:${NC}"
    echo "  • Node.js:           $NODE_VERSION"
    echo "  • npm:               $NPM_VERSION"
    echo "  • PostgreSQL:        15"
    echo "  • Nginx:             $(nginx -v 2>&1 | cut -d'/' -f2)"
    echo "  • Tailscale:         $(tailscale version | head -n1)"
    if command -v docker &> /dev/null; then
        echo "  • Docker:            $(docker --version | cut -d' ' -f3 | tr -d ',')"
    fi
    echo ""
    echo -e "${CYAN}Service Ports:${NC}"
    echo "  • Nginx HTTPS:       ${NGINX_HTTPS_PORT}"
    echo "  • N8N:               ${N8N_PORT}"
    echo "  • Flowise:           ${FLOWISE_PORT}"
    echo "  • LiteLLM:           ${LITELLM_PORT}"
    echo "  • Langfuse:          ${LANGFUSE_PORT}"
    if [[ "${OPENCLAW_ENABLED:-false}" == "true" ]]; then
        echo "  • OpenClaw:          ${OPENCLAW_API_PORT}"
        echo "  • Qdrant:            ${QDRANT_PORT}"
    fi
    echo ""
    echo -e "${CYAN}Database Status:${NC}"
    echo "  • PostgreSQL:        $(systemctl is-active postgresql)"
    echo "  • Databases:         n8n, flowise, litellm, langfuse"
    echo ""
    echo -e "${CYAN}Security:${NC}"
    echo "  • N8N Encryption:    ✓ Configured"
    echo "  • LiteLLM Master:    ✓ Configured"
    echo "  • Langfuse Auth:     ✓ Configured"
    if [[ "${OPENCLAW_ENABLED:-false}" == "true" ]]; then
        echo "  • Qdrant API Key:    ✓ Configured"
        echo "  • OpenClaw API:      ✓ Configured"
    fi
    echo ""
    echo -e "${CYAN}Configuration:${NC}"
    echo "  • Environment file:  $CONFIG_FILE"
    echo "  • State file:        $STATE_FILE"
    echo "  • Log directory:     $LOG_DIR"
    echo ""
    echo -e "${YELLOW}Important Credentials (SAVE THESE):${NC}"
    echo ""
    echo "  N8N Database:"
    echo "    Password: ${N8N_DB_PASSWORD:0:8}...${N8N_DB_PASSWORD: -4}"
    echo ""
    echo "  Flowise:"
    echo "    Username: admin"
    echo "    Password: ${FLOWISE_PASSWORD:0:8}...${FLOWISE_PASSWORD: -4}"
    echo ""
    echo "  LiteLLM:"
    echo "    Master Key: ${LITELLM_MASTER_KEY:0:8}...${LITELLM_MASTER_KEY: -4}"
    echo ""
    echo "  Langfuse:"
    echo "    Public Key:  ${LANGFUSE_INIT_PROJECT_PUBLIC}"
    echo "    Secret Key:  ${LANGFUSE_INIT_PROJECT_SECRET:0:8}...${LANGFUSE_INIT_PROJECT_SECRET: -4}"
    echo ""
    if [[ "${OPENCLAW_ENABLED:-false}" == "true" ]]; then
        echo "  OpenClaw:"
        echo "    API Key: ${OPENCLAW_API_KEY:0:8}...${OPENCLAW_API_KEY: -4}"
        echo ""
        echo "  Qdrant:"
        echo "    API Key: ${QDRANT_API_KEY:0:8}...${QDRANT_API_KEY: -4}"
        echo ""
    fi
    echo -e "${GREEN}Full credentials stored in: $CONFIG_FILE${NC}"
    echo ""
    echo -e "${CYAN}Next Steps:${NC}"
    echo "  1. Review configuration: cat $CONFIG_FILE"
    echo "  2. Run deployment:       $SCRIPT_DIR/2-deploy-services.sh"
    echo ""
    echo -e "${YELLOW}⚠  Keep $CONFIG_FILE secure - it contains sensitive credentials${NC}"
    echo ""
}

# ============================================================================
# Execute Main
# ============================================================================

main "$@"

