#!/bin/bash

set -euo pipefail

# ============================================================================
# AI Platform - System Setup Script v7.0
# ============================================================================

readonly SCRIPT_VERSION="7.0"
readonly PROJECT_ROOT="${HOME}/AIPlatformAutomation"
readonly SCRIPT_DIR="${PROJECT_ROOT}/scripts"
readonly STACKS_DIR="${PROJECT_ROOT}/stacks"
readonly DATA_DIR="${PROJECT_ROOT}/data"
readonly LOG_DIR="${PROJECT_ROOT}/logs"
readonly ENV_FILE="${PROJECT_ROOT}/.env"
readonly LOG_FILE="${LOG_DIR}/setup-$(date +%Y%m%d-%H%M%S).log"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Icons
readonly CHECK_MARK="✓"
readonly CROSS_MARK="✗"
readonly INFO_MARK="ℹ"
readonly WARN_MARK="⚠"

# ============================================================================
# Utility Functions
# ============================================================================

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}${CHECK_MARK} $*${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}${CROSS_MARK} $*${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}${WARN_MARK} $*${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}${INFO_MARK} $*${NC}" | tee -a "$LOG_FILE"
}

generate_random_string() {
    local length="${1:-32}"
    LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
}

generate_api_key() {
    echo "sk-$(generate_random_string 48)"
}

command_exists() {
    command -v "$1" &> /dev/null
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

preflight_checks() {
    info "Running pre-flight checks..."
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root"
        exit 1
    fi
    
    # Check internet connectivity
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        error "No internet connectivity"
        exit 1
    fi
    
    # Check available disk space (minimum 10GB)
    local available_space=$(df -BG "${HOME}" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $available_space -lt 10 ]]; then
        warn "Low disk space: ${available_space}GB available"
    fi
    
    success "Pre-flight checks completed"
}

# ============================================================================
# Directory Setup
# ============================================================================

setup_directories() {
    info "Setting up directory structure..."
    
    # Create main directories
    mkdir -p "${PROJECT_ROOT}"
    mkdir -p "${SCRIPT_DIR}"
    mkdir -p "${STACKS_DIR}"
    mkdir -p "${LOG_DIR}"
    
    # Create data directories for each service
    mkdir -p "${DATA_DIR}"/{litellm,ollama,dify,n8n,signal,postgres,redis,weaviate}
    mkdir -p "${DATA_DIR}/dify/sandbox"
    
    success "Directory structure created"
}

# ============================================================================
# Environment File Generation
# ============================================================================

generate_env_file() {
    info "Generating environment configuration..."
    
    # Generate secure credentials
    local litellm_master_key=$(generate_api_key)
    local dify_db_user="dify_$(generate_random_string 8)"
    local dify_db_password=$(generate_random_string 32)
    local dify_secret_key=$(generate_random_string 64)
    local redis_password=$(generate_random_string 32)
    local weaviate_api_key=$(generate_api_key)
    local n8n_encryption_key=$(generate_random_string 32)
    local n8n_jwt_secret=$(generate_random_string 32)
    
    # Detect GPU
    local gpu_available="false"
    if command_exists nvidia-smi && nvidia-smi &> /dev/null; then
        gpu_available="true"
    fi
    
    # Get Tailscale IP if available
    local tailscale_ip="127.0.0.1"
    if command_exists tailscale; then
        tailscale_ip=$(tailscale ip -4 2>/dev/null || echo "127.0.0.1")
    fi
    
    # Create .env file
    cat > "$ENV_FILE" <<EOF
# =============================================================================
# AI Platform Environment Configuration
# Generated: $(date)
# =============================================================================

# =============================================================================
# Directory Paths
# =============================================================================
DATA_DIR=${DATA_DIR}
SCRIPT_DIR=${SCRIPT_DIR}
STACKS_DIR=${STACKS_DIR}
PROJECT_ROOT=${PROJECT_ROOT}
ENV_FILE=${ENV_FILE}

# =============================================================================
# LiteLLM Configuration
# =============================================================================
LITELLM_MASTER_KEY=${litellm_master_key}
LITELLM_PORT=4000
LITELLM_DATABASE_URL=postgresql://postgres:postgres@localhost:5432/litellm

# =============================================================================
# Ollama Configuration
# =============================================================================
OLLAMA_PORT=11434
OLLAMA_HOST=0.0.0.0

# =============================================================================
# Dify Configuration
# =============================================================================
DIFY_WEB_PORT=3000
DIFY_API_PORT=5001
DIFY_DB_USER=${dify_db_user}
DIFY_DB_PASSWORD=${dify_db_password}
DIFY_SECRET_KEY=${dify_secret_key}

# PostgreSQL
POSTGRES_USER=${dify_db_user}
POSTGRES_PASSWORD=${dify_db_password}
POSTGRES_DB=dify
POSTGRES_PORT=5432

# Redis
REDIS_PASSWORD=${redis_password}
REDIS_PORT=6379

# Weaviate
WEAVIATE_API_KEY=${weaviate_api_key}
WEAVIATE_PORT=8080

# =============================================================================
# n8n Configuration
# =============================================================================
N8N_PORT=5678
N8N_ENCRYPTION_KEY=${n8n_encryption_key}
N8N_USER_MANAGEMENT_JWT_SECRET=${n8n_jwt_secret}
N8N_WEBHOOK_URL=http://localhost:5678/

# =============================================================================
# Signal API Configuration
# =============================================================================
SIGNAL_API_PORT=8080

# =============================================================================
# System Configuration
# =============================================================================
GPU_AVAILABLE=${gpu_available}
TAILSCALE_IP=${tailscale_ip}
TZ=UTC

# =============================================================================
# Docker Configuration
# =============================================================================
COMPOSE_PROJECT_NAME=ai-platform
DOCKER_BUILDKIT=1
COMPOSE_DOCKER_CLI_BUILD=1
EOF

    chmod 600 "$ENV_FILE"
    success "Environment file generated: $ENV_FILE"
    
    info "Generated credentials (saved to $ENV_FILE):"
    echo "  • LiteLLM Master Key: ${litellm_master_key:0:20}..."
    echo "  • Dify DB User: ${dify_db_user}"
    echo "  • GPU Available: ${gpu_available}"
    echo "  • Tailscale IP: ${tailscale_ip}"
}

# ============================================================================
# Create Docker Compose Files
# ============================================================================

create_compose_files() {
    info "Creating Docker Compose files..."
    
    # 1. LiteLLM Compose
    cat > "${STACKS_DIR}/litellm-compose.yml" <<'EOF'
services:
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm
    restart: unless-stopped
    environment:
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
      - DATABASE_URL=${LITELLM_DATABASE_URL}
      - OLLAMA_API_BASE=http://ollama:11434
    ports:
      - "${LITELLM_PORT:-4000}:4000"
    volumes:
      - ${DATA_DIR}/litellm:/app/config
    networks:
      - ai-platform-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  ai-platform-network:
    external: true
EOF

    # 2. Ollama Compose
    cat > "${STACKS_DIR}/ollama-compose.yml" <<'EOF'
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    ports:
      - "${OLLAMA_PORT:-11434}:11434"
    volumes:
      - ${DATA_DIR}/ollama:/root/.ollama
    networks:
      - ai-platform-network
    environment:
      - OLLAMA_HOST=0.0.0.0
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    profiles:
      - gpu

networks:
  ai-platform-network:
    external: true
EOF

    # 3. Dify Compose
    cat > "${STACKS_DIR}/dify-compose.yml" <<'EOF'
services:
  postgres:
    image: postgres:15-alpine
    container_name: dify-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - ${DATA_DIR}/postgres:/var/lib/postgresql/data
    networks:
      - ai-platform-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: dify-redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - ${DATA_DIR}/redis:/data
    networks:
      - ai-platform-network
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  weaviate:
    image: semitechnologies/weaviate:latest
    container_name: dify-weaviate
    restart: unless-stopped
    environment:
      AUTHENTICATION_APIKEY_ENABLED: 'true'
      AUTHENTICATION_APIKEY_ALLOWED_KEYS: ${WEAVIATE_API_KEY}
      PERSISTENCE_DATA_PATH: /var/lib/weaviate
      QUERY_DEFAULTS_LIMIT: 25
      DEFAULT_VECTORIZER_MODULE: none
      CLUSTER_HOSTNAME: node1
    volumes:
      - ${DATA_DIR}/weaviate:/var/lib/weaviate
    networks:
      - ai-platform-network

  dify-api:
    image: langgenius/dify-api:latest
    container_name: dify-api
    restart: unless-stopped
    depends_on:
      - postgres
      - redis
      - weaviate
    environment:
      MODE: api
      LOG_LEVEL: INFO
      SECRET_KEY: ${DIFY_SECRET_KEY}
      DB_USERNAME: ${POSTGRES_USER}
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_HOST: postgres
      DB_PORT: 5432
      DB_DATABASE: ${POSTGRES_DB}
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      REDIS_DB: 0
      CELERY_BROKER_URL: redis://:${REDIS_PASSWORD}@redis:6379/1
      VECTOR_STORE: weaviate
      WEAVIATE_ENDPOINT: http://weaviate:8080
      WEAVIATE_API_KEY: ${WEAVIATE_API_KEY}
    volumes:
      - ${DATA_DIR}/dify:/app/api/storage
    networks:
      - ai-platform-network

  dify-worker:
    image: langgenius/dify-api:latest
    container_name: dify-worker
    restart: unless-stopped
    depends_on:
      - postgres
      - redis
    environment:
      MODE: worker
      LOG_LEVEL: INFO
      SECRET_KEY: ${DIFY_SECRET_KEY}
      DB_USERNAME: ${POSTGRES_USER}
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_HOST: postgres
      DB_PORT: 5432
      DB_DATABASE: ${POSTGRES_DB}
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      REDIS_DB: 0
      CELERY_BROKER_URL: redis://:${REDIS_PASSWORD}@redis:6379/1
      VECTOR_STORE: weaviate
      WEAVIATE_ENDPOINT: http://weaviate:8080
      WEAVIATE_API_KEY: ${WEAVIATE_API_KEY}
    volumes:
      - ${DATA_DIR}/dify:/app/api/storage
    networks:
      - ai-platform-network

  dify-web:
    image: langgenius/dify-web:latest
    container_name: dify-web
    restart: unless-stopped
    depends_on:
      - dify-api
    environment:
      CONSOLE_API_URL: http://dify-api:5001
      APP_API_URL: http://dify-api:5001
    networks:
      - ai-platform-network

  dify-nginx:
    image: nginx:alpine
    container_name: dify-nginx
    restart: unless-stopped
    depends_on:
      - dify-api
      - dify-web
    ports:
      - "${DIFY_WEB_PORT:-3000}:80"
    volumes:
      - ${STACKS_DIR}/nginx.conf:/etc/nginx/nginx.conf:ro
    networks:
      - ai-platform-network

  dify-sandbox:
    image: langgenius/dify-sandbox:latest
    container_name: dify-sandbox
    restart: unless-stopped
    environment:
      API_KEY: ${DIFY_SECRET_KEY}
      GIN_MODE: release
      WORKER_TIMEOUT: 15
    volumes:
      - ${DATA_DIR}/dify/sandbox:/dependencies
    networks:
      - ai-platform-network

networks:
  ai-platform-network:
    external: true
EOF

    # 4. N8N Compose
    cat > "${STACKS_DIR}/n8n-compose.yml" <<'EOF'
services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "${N8N_PORT:-5678}:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=changeme
      - N8N_HOST=0.0.0.0
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - NODE_ENV=production
      - WEBHOOK_URL=${N8N_WEBHOOK_URL}
      - GENERIC_TIMEZONE=UTC
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_USER_MANAGEMENT_JWT_SECRET=${N8N_USER_MANAGEMENT_JWT_SECRET}
    volumes:
      - ${DATA_DIR}/n8n:/home/node/.n8n
    networks:
      - ai-platform-network

networks:
  ai-platform-network:
    external: true
EOF

    # 5. Signal Compose
    cat > "${STACKS_DIR}/signal-compose.yml" <<'EOF'
services:
  signal-api:
    image: bbernhard/signal-cli-rest-api:latest
    container_name: signal-api
    restart: unless-stopped
    ports:
      - "${SIGNAL_API_PORT:-8080}:8080"
    environment:
      - MODE=native
    volumes:
      - ${DATA_DIR}/signal:/home/.local/share/signal-cli
    networks:
      - ai-platform-network

networks:
  ai-platform-network:
    external: true
EOF

    # 6. Nginx Config
    cat > "${STACKS_DIR}/nginx.conf" <<'EOF'
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    upstream dify-api {
        server dify-api:5001;
    }

    upstream dify-web {
        server dify-web:3000;
    }

    server {
        listen 80;
        server_name _;

        client_max_body_size 15M;

        location /console/api {
            proxy_pass http://dify-api;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_buffering off;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
        }

        location /api {
            proxy_pass http://dify-api;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_buffering off;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
        }

        location /v1 {
            proxy_pass http://dify-api;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_buffering off;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
        }

        location /files {
            proxy_pass http://dify-api;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location / {
            proxy_pass http://dify-web;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }
    }
}
EOF

    success "Docker Compose files created in ${STACKS_DIR}"
}

# ============================================================================
# System Update
# ============================================================================

update_system() {
    info "Updating system packages..."
    sudo apt-get update
    sudo apt-get upgrade -y
    success "System packages updated"
}

# ============================================================================
# Install Dependencies
# ============================================================================

install_dependencies() {
    info "Installing required dependencies..."
    
    local packages=(
        curl
        wget
        git
        apt-transport-https
        ca-certificates
        gnupg
        lsb-release
        jq
        htop
        net-tools
    )
    
    sudo apt-get install -y "${packages[@]}"
    success "Dependencies installed"
}

# ============================================================================
# Docker Installation
# ============================================================================

install_docker() {
    if command_exists docker; then
        local docker_version=$(docker --version)
        info "Docker already installed: $docker_version"
    else
        info "Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        rm get-docker.sh
        success "Docker installed"
    fi
    
    # Ensure docker group exists and add user
    info "Adding user to docker group..."
    if ! getent group docker > /dev/null 2>&1; then
        sudo groupadd docker
    fi
    sudo usermod -aG docker "$USER"
    
    # Start and enable Docker
    sudo systemctl enable docker
    sudo systemctl start docker
    
    success "Docker configured"
}

# ============================================================================
# Docker Compose Installation
# ============================================================================

install_docker_compose() {
    if command_exists docker-compose; then
        local compose_version=$(docker-compose --version)
        info "Docker Compose already installed: $compose_version"
    else
        info "Installing Docker Compose..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        success "Docker Compose installed"
    fi
}

# ============================================================================
# Summary Display
# ============================================================================

display_summary() {
    echo ""
    echo "========================================"
    echo "Setup Complete!"
    echo "========================================"
    echo ""
    echo "Configuration saved to: $ENV_FILE"
    echo ""
    echo "Credentials (from $ENV_FILE):"
    echo "  • LiteLLM Key: $(grep '^LITELLM_MASTER_KEY=' "$ENV_FILE" | cut -d'=' -f2)"
    echo "  • Dify DB User: $(grep '^DIFY_DB_USER=' "$ENV_FILE" | cut -d'=' -f2)"
    echo "  • GPU Available: $(grep '^GPU_AVAILABLE=' "$ENV_FILE" | cut -d'=' -f2)"
    echo "  • Tailscale IP: $(grep '^TAILSCALE_IP=' "$ENV_FILE" | cut -d'=' -f2)"
    echo ""
    echo "Next Steps:"
    echo "  1. IMPORTANT: Log out and log back in (or run: newgrp docker)"
    echo "  2. Run: cd $SCRIPT_DIR"
    echo "  3. Run: ./2-deploy-services.sh"
    echo ""
    echo "Log file: $LOG_FILE"
    echo "========================================"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    echo ""
    echo "========================================"
    echo "AI Platform - System Setup v${SCRIPT_VERSION}"
    echo "========================================"
    echo ""
    
    info "Location: $PROJECT_ROOT"
    info "Started: $(date)"
    
    preflight_checks
    setup_directories
    generate_env_file
    create_compose_files
    
    info "[1/5] Updating system packages..."
    update_system
    
    info "[2/5] Installing dependencies..."
    install_dependencies
    
    info "[3/5] Installing and configuring Docker..."
    install_docker
    
    info "[4/5] Installing Docker Compose..."
    install_docker_compose
    
    info "[5/5] Finalizing setup..."
    chmod +x "${SCRIPT_DIR}"/*.sh 2>/dev/null || true
    
    display_summary
}

main "$@"
