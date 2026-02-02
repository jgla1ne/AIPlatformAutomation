#!/bin/bash
set -euo pipefail

# ============================================================================
# AI Platform - System Setup Script
# Version: 19.0 - ALL FIXES APPLIED
# ============================================================================

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOGS_DIR="${PROJECT_ROOT}/logs"
mkdir -p "$LOGS_DIR"
LOGFILE="${LOGS_DIR}/setup-${TIMESTAMP}.log"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $1" | tee -a "$LOGFILE"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1" | tee -a "$LOGFILE"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOGFILE"
}

log_error() {
    echo -e "${RED}✗${NC} $1" | tee -a "$LOGFILE"
}

log_step() {
    echo -e "\n${CYAN}[$1]${NC} $2" | tee -a "$LOGFILE"
}

# Error handler
error_handler() {
    log_error "Setup failed at line $1"
    log_error "Check log: $LOGFILE"
    exit 1
}
trap 'error_handler $LINENO' ERR

# ============================================================================
# BANNER
# ============================================================================
show_banner() {
    clear
    cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║          AI PLATFORM - SYSTEM SETUP v19.0                  ║
║           Complete Self-Hosted AI Infrastructure           ║
║                                                            ║
║  Services:                                                 ║
║    • Ollama (Local LLMs)                                   ║
║    • LiteLLM (LLM Gateway)                                 ║
║    • Vector DBs (Weaviate, Qdrant, Milvus)                ║
║    • Dify (LLM Platform)                                   ║
║    • n8n (Workflow Automation)                             ║
║    • AnythingLLM (Document Chat)                           ║
║    • Flowise (Visual AI Builder)                           ║
║    • Signal API (Messaging)                                ║
║    • ClawdBot (AI Assistant)                               ║
║    • Nginx (Reverse Proxy)                                 ║
║    • Tailscale (VPN Access)                                ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝

EOF
}

# ============================================================================
# PREREQUISITES CHECK
# ============================================================================
check_prerequisites() {
    log_step "1/12" "Checking prerequisites"
    
    local missing_tools=()
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        missing_tools+=("docker")
    else
        log_success "Docker found: $(docker --version | cut -d' ' -f3)"
    fi
    
    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        missing_tools+=("docker-compose")
    else
        log_success "Docker Compose found: $(docker compose version | cut -d' ' -f4)"
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        log_warning "jq not found (optional, recommended)"
    else
        log_success "jq found: $(jq --version)"
    fi
    
    # Check curl
    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    else
        log_success "curl found"
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Install missing tools:"
        echo "  Ubuntu/Debian: sudo apt-get install ${missing_tools[*]}"
        echo "  CentOS/RHEL: sudo yum install ${missing_tools[*]}"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# ============================================================================
# SET DEFAULT VALUES - MUST BE CALLED BEFORE COLLECT_CONFIGURATION
# ============================================================================
set_default_values() {
    log_step "2/12" "Setting default values"
    
    # Domain configuration
    DOMAIN=${DOMAIN:-"localhost"}
    
    # Service enablement flags
    ENABLE_OLLAMA=${ENABLE_OLLAMA:-"true"}
    ENABLE_LITELLM=${ENABLE_LITELLM:-"true"}
    ENABLE_WEAVIATE=${ENABLE_WEAVIATE:-"true"}
    ENABLE_QDRANT=${ENABLE_QDRANT:-"true"}
    ENABLE_MILVUS=${ENABLE_MILVUS:-"false"}
    ENABLE_DIFY=${ENABLE_DIFY:-"true"}
    ENABLE_N8N=${ENABLE_N8N:-"true"}
    ENABLE_ANYTHINGLLM=${ENABLE_ANYTHINGLLM:-"true"}
    ENABLE_FLOWISE=${ENABLE_FLOWISE:-"true"}
    ENABLE_LIBRECHAT=${ENABLE_LIBRECHAT:-"false"}
    ENABLE_SIGNAL=${ENABLE_SIGNAL:-"false"}
    ENABLE_CLAWDBOT=${ENABLE_CLAWDBOT:-"false"}
    ENABLE_NGINX=${ENABLE_NGINX:-"true"}
    ENABLE_TAILSCALE=${ENABLE_TAILSCALE:-"false"}
    
    # Database configuration
    POSTGRES_USER=${POSTGRES_USER:-"aiuser"}
    POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-"$(openssl rand -base64 32)"}
    POSTGRES_DB=${POSTGRES_DB:-"aiplatform"}
    POSTGRES_PORT=${POSTGRES_PORT:-"5432"}
    POSTGRES_VERSION=${POSTGRES_VERSION:-"16-alpine"}
    
    # Redis configuration
    REDIS_PASSWORD=${REDIS_PASSWORD:-"$(openssl rand -base64 32)"}
    REDIS_PORT=${REDIS_PORT:-"6379"}
    REDIS_VERSION=${REDIS_VERSION:-"7-alpine"}
    
    # MinIO configuration
    MINIO_ROOT_USER=${MINIO_ROOT_USER:-"minioadmin"}
    MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD:-"$(openssl rand -base64 32)"}
    MINIO_PORT=${MINIO_PORT:-"9000"}
    MINIO_CONSOLE_PORT=${MINIO_CONSOLE_PORT:-"9001"}
    MINIO_VERSION=${MINIO_VERSION:-"latest"}
    
    # Ollama configuration
    OLLAMA_PORT=${OLLAMA_PORT:-"11434"}
    OLLAMA_VERSION=${OLLAMA_VERSION:-"latest"}
    
    # LiteLLM configuration
    LITELLM_PORT=${LITELLM_PORT:-"4000"}
    LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY:-"sk-$(openssl rand -hex 16)"}
    LITELLM_VERSION=${LITELLM_VERSION:-"main-latest"}
    
    # Weaviate configuration
    WEAVIATE_PORT=${WEAVIATE_PORT:-"8080"}
    WEAVIATE_GRPC_PORT=${WEAVIATE_GRPC_PORT:-"50051"}
    WEAVIATE_VERSION=${WEAVIATE_VERSION:-"1.25.0"}
    
    # Qdrant configuration
    QDRANT_PORT=${QDRANT_PORT:-"6333"}
    QDRANT_GRPC_PORT=${QDRANT_GRPC_PORT:-"6334"}
    QDRANT_API_KEY=${QDRANT_API_KEY:-"$(openssl rand -base64 32)"}
    QDRANT_VERSION=${QDRANT_VERSION:-"latest"}
    
    # Dify configuration
    DIFY_PORT=${DIFY_PORT:-"3000"}
    DIFY_API_PORT=${DIFY_API_PORT:-"5001"}
    DIFY_SECRET_KEY=${DIFY_SECRET_KEY:-"$(openssl rand -base64 32)"}
    DIFY_DB_NAME=${DIFY_DB_NAME:-"dify"}
    DIFY_VERSION=${DIFY_VERSION:-"0.6.13"}
    
    # n8n configuration
    N8N_PORT=${N8N_PORT:-"5678"}
    N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY:-"$(openssl rand -base64 32)"}
    N8N_DB_NAME=${N8N_DB_NAME:-"n8n"}
    N8N_VERSION=${N8N_VERSION:-"latest"}
    
    # AnythingLLM configuration
    ANYTHINGLLM_PORT=${ANYTHINGLLM_PORT:-"3001"}
    ANYTHINGLLM_JWT_SECRET=${ANYTHINGLLM_JWT_SECRET:-"$(openssl rand -base64 32)"}
    ANYTHINGLLM_VERSION=${ANYTHINGLLM_VERSION:-"latest"}
    
    # Flowise configuration
    FLOWISE_PORT=${FLOWISE_PORT:-"3002"}
    FLOWISE_USERNAME=${FLOWISE_USERNAME:-"admin"}
    FLOWISE_PASSWORD=${FLOWISE_PASSWORD:-"$(openssl rand -base64 16)"}
    FLOWISE_SECRETKEY=${FLOWISE_SECRETKEY:-"$(openssl rand -base64 32)"}
    FLOWISE_VERSION=${FLOWISE_VERSION:-"latest"}
    
    log_success "Default values set"
}

# ============================================================================
# COLLECT CONFIGURATION
# ============================================================================
collect_configuration() {
    log_step "3/12" "Collecting configuration"
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  CONFIGURATION${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Domain
    read -p "Enter domain [${DOMAIN}]: " input_domain
    DOMAIN=${input_domain:-$DOMAIN}
    
    echo ""
    echo -e "${YELLOW}Select services to enable (y/n):${NC}"
    
    # Ollama
    read -p "Enable Ollama? [Y/n]: " enable_ollama
    ENABLE_OLLAMA=${enable_ollama:-"y"}
    [[ "$ENABLE_OLLAMA" =~ ^[Yy]$ ]] && ENABLE_OLLAMA="true" || ENABLE_OLLAMA="false"
    
    # LiteLLM
    read -p "Enable LiteLLM? [Y/n]: " enable_litellm
    ENABLE_LITELLM=${enable_litellm:-"y"}
    [[ "$ENABLE_LITELLM" =~ ^[Yy]$ ]] && ENABLE_LITELLM="true" || ENABLE_LITELLM="false"
    
    # Weaviate
    read -p "Enable Weaviate? [Y/n]: " enable_weaviate
    ENABLE_WEAVIATE=${enable_weaviate:-"y"}
    [[ "$ENABLE_WEAVIATE" =~ ^[Yy]$ ]] && ENABLE_WEAVIATE="true" || ENABLE_WEAVIATE="false"
    
    # Qdrant
    read -p "Enable Qdrant? [Y/n]: " enable_qdrant
    ENABLE_QDRANT=${enable_qdrant:-"y"}
    [[ "$ENABLE_QDRANT" =~ ^[Yy]$ ]] && ENABLE_QDRANT="true" || ENABLE_QDRANT="false"
    
    # Dify
    read -p "Enable Dify? [Y/n]: " enable_dify
    ENABLE_DIFY=${enable_dify:-"y"}
    [[ "$ENABLE_DIFY" =~ ^[Yy]$ ]] && ENABLE_DIFY="true" || ENABLE_DIFY="false"
    
    # n8n
    read -p "Enable n8n? [Y/n]: " enable_n8n
    ENABLE_N8N=${enable_n8n:-"y"}
    [[ "$ENABLE_N8N" =~ ^[Yy]$ ]] && ENABLE_N8N="true" || ENABLE_N8N="false"
    
    # AnythingLLM
    read -p "Enable AnythingLLM? [Y/n]: " enable_anythingllm
    ENABLE_ANYTHINGLLM=${enable_anythingllm:-"y"}
    [[ "$ENABLE_ANYTHINGLLM" =~ ^[Yy]$ ]] && ENABLE_ANYTHINGLLM="true" || ENABLE_ANYTHINGLLM="false"
    
    # Flowise
    read -p "Enable Flowise? [Y/n]: " enable_flowise
    ENABLE_FLOWISE=${enable_flowise:-"y"}
    [[ "$ENABLE_FLOWISE" =~ ^[Yy]$ ]] && ENABLE_FLOWISE="true" || ENABLE_FLOWISE="false"
    
    # Nginx
    read -p "Enable Nginx reverse proxy? [Y/n]: " enable_nginx
    ENABLE_NGINX=${enable_nginx:-"y"}
    [[ "$ENABLE_NGINX" =~ ^[Yy]$ ]] && ENABLE_NGINX="true" || ENABLE_NGINX="false"
    
    log_success "Configuration collected"
}

# ============================================================================
# CREATE DIRECTORIES
# ============================================================================
create_directories() {
    log_step "4/12" "Creating directory structure"
    
    # Main directories
    mkdir -p "${PROJECT_ROOT}"/{data,logs,backups,stacks,scripts}
    
    # Data directories
    mkdir -p "${PROJECT_ROOT}/data"/{postgres,redis,minio,ollama,weaviate,qdrant,milvus,dify,n8n,anythingllm,flowise,librechat,nginx}
    
    # Stack directories
    mkdir -p "${PROJECT_ROOT}/stacks"/{infrastructure,ollama,litellm,weaviate,qdrant,milvus,dify,n8n,anythingllm,flowise,librechat,signal,clawdbot,nginx,tailscale}
    
    log_success "Directory structure created"
}

# ============================================================================
# SAVE CREDENTIALS
# ============================================================================
save_credentials() {
    log_step "5/12" "Saving credentials"
    
    # Backup existing .env if it exists
    if [[ -f "${PROJECT_ROOT}/.env" ]]; then
        cp "${PROJECT_ROOT}/.env" "${PROJECT_ROOT}/.env.backup.${TIMESTAMP}"
        log_info "Backed up existing .env"
    fi
    
    # Create new .env file
    cat > "${PROJECT_ROOT}/.env" << EOF
# AI Platform Configuration
# Generated: $(date)

# Domain Configuration
DOMAIN=${DOMAIN}

# Service Enablement
ENABLE_OLLAMA=${ENABLE_OLLAMA}
ENABLE_LITELLM=${ENABLE_LITELLM}
ENABLE_WEAVIATE=${ENABLE_WEAVIATE}
ENABLE_QDRANT=${ENABLE_QDRANT}
ENABLE_MILVUS=${ENABLE_MILVUS}
ENABLE_DIFY=${ENABLE_DIFY}
ENABLE_N8N=${ENABLE_N8N}
ENABLE_ANYTHINGLLM=${ENABLE_ANYTHINGLLM}
ENABLE_FLOWISE=${ENABLE_FLOWISE}
ENABLE_LIBRECHAT=${ENABLE_LIBRECHAT}
ENABLE_SIGNAL=${ENABLE_SIGNAL}
ENABLE_CLAWDBOT=${ENABLE_CLAWDBOT}
ENABLE_NGINX=${ENABLE_NGINX}
ENABLE_TAILSCALE=${ENABLE_TAILSCALE}

# PostgreSQL
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_PORT=${POSTGRES_PORT}
POSTGRES_VERSION=${POSTGRES_VERSION}

# Redis
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_PORT=${REDIS_PORT}
REDIS_VERSION=${REDIS_VERSION}

# MinIO
MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
MINIO_PORT=${MINIO_PORT}
MINIO_CONSOLE_PORT=${MINIO_CONSOLE_PORT}
MINIO_VERSION=${MINIO_VERSION}

# Ollama
OLLAMA_PORT=${OLLAMA_PORT}
OLLAMA_VERSION=${OLLAMA_VERSION}

# LiteLLM
LITELLM_PORT=${LITELLM_PORT}
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
LITELLM_VERSION=${LITELLM_VERSION}

# Weaviate
WEAVIATE_PORT=${WEAVIATE_PORT}
WEAVIATE_GRPC_PORT=${WEAVIATE_GRPC_PORT}
WEAVIATE_VERSION=${WEAVIATE_VERSION}

# Qdrant
QDRANT_PORT=${QDRANT_PORT}
QDRANT_GRPC_PORT=${QDRANT_GRPC_PORT}
QDRANT_API_KEY=${QDRANT_API_KEY}
QDRANT_VERSION=${QDRANT_VERSION}

# Dify
DIFY_PORT=${DIFY_PORT}
DIFY_API_PORT=${DIFY_API_PORT}
DIFY_SECRET_KEY=${DIFY_SECRET_KEY}
DIFY_DB_NAME=${DIFY_DB_NAME}
DIFY_VERSION=${DIFY_VERSION}

# n8n
N8N_PORT=${N8N_PORT}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_DB_NAME=${N8N_DB_NAME}
N8N_VERSION=${N8N_VERSION}

# AnythingLLM
ANYTHINGLLM_PORT=${ANYTHINGLLM_PORT}
ANYTHINGLLM_JWT_SECRET=${ANYTHINGLLM_JWT_SECRET}
ANYTHINGLLM_VERSION=${ANYTHINGLLM_VERSION}

# Flowise
FLOWISE_PORT=${FLOWISE_PORT}
FLOWISE_USERNAME=${FLOWISE_USERNAME}
FLOWISE_PASSWORD=${FLOWISE_PASSWORD}
FLOWISE_SECRETKEY=${FLOWISE_SECRETKEY}
FLOWISE_VERSION=${FLOWISE_VERSION}
EOF

    chmod 600 "${PROJECT_ROOT}/.env"
    log_success "Credentials saved to .env"
}

# ============================================================================
# CREATE DOCKER NETWORK
# ============================================================================
create_docker_network() {
    log_step "6/12" "Creating Docker network"
    
    if docker network inspect ai-network &>/dev/null; then
        log_info "Network 'ai-network' already exists"
    else
        docker network create ai-network
        log_success "Network 'ai-network' created"
    fi
}

# ============================================================================
# GENERATE STACK CONFIGS - DOCKER COMPOSE V2 FORMAT (NO VERSION ATTRIBUTE)
# ============================================================================
generate_stack_configs() {
    log_step "7/12" "Generating Docker Compose configurations"
    
    # Source the .env file
    set -a
    source "${PROJECT_ROOT}/.env"
    set +a
    
    # ========================================================================
    # INFRASTRUCTURE STACK
    # ========================================================================
    cat > "${PROJECT_ROOT}/stacks/infrastructure/docker-compose.yml" << 'EOF'
networks:
  ai-network:
    external: true

services:
  postgres:
    image: postgres:${POSTGRES_VERSION}
    container_name: ai-postgres
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    ports:
      - "${POSTGRES_PORT}:5432"
    volumes:
      - ../../data/postgres:/var/lib/postgresql/data
    networks:
      - ai-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:${REDIS_VERSION}
    container_name: ai-redis
    command: redis-server --requirepass ${REDIS_PASSWORD}
    ports:
      - "${REDIS_PORT}:6379"
    volumes:
      - ../../data/redis:/data
    networks:
      - ai-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  minio:
    image: minio/minio:${MINIO_VERSION}
    container_name: ai-minio
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
    ports:
      - "${MINIO_PORT}:9000"
      - "${MINIO_CONSOLE_PORT}:9001"
    volumes:
      - ../../data/minio:/data
    networks:
      - ai-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 20s
      retries: 3
EOF

    log_success "Infrastructure stack configuration generated"
    
    # ========================================================================
    # OLLAMA STACK
    # ========================================================================
    if [[ "${ENABLE_OLLAMA}" == "true" ]]; then
        cat > "${PROJECT_ROOT}/stacks/ollama/docker-compose.yml" << 'EOF'
networks:
  ai-network:
    external: true

services:
  ollama:
    image: ollama/ollama:${OLLAMA_VERSION}
    container_name: ai-ollama
    ports:
      - "${OLLAMA_PORT}:11434"
    volumes:
      - ../../data/ollama:/root/.ollama
    networks:
      - ai-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/tags"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF
        log_success "Ollama stack configuration generated"
    fi
    
    # ========================================================================
    # LITELLM STACK
    # ========================================================================
    if [[ "${ENABLE_LITELLM}" == "true" ]]; then
        cat > "${PROJECT_ROOT}/stacks/litellm/docker-compose.yml" << 'EOF'
networks:
  ai-network:
    external: true

services:
  litellm:
    image: ghcr.io/berriai/litellm:${LITELLM_VERSION}
    container_name: ai-litellm
    environment:
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
      DATABASE_URL: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@ai-postgres:5432/${POSTGRES_DB}
    ports:
      - "${LITELLM_PORT}:4000"
    networks:
      - ai-network
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF
        log_success "LiteLLM stack configuration generated"
    fi
    
    # ========================================================================
    # WEAVIATE STACK
    # ========================================================================
    if [[ "${ENABLE_WEAVIATE}" == "true" ]]; then
        cat > "${PROJECT_ROOT}/stacks/weaviate/docker-compose.yml" << 'EOF'
networks:
  ai-network:
    external: true

services:
  weaviate:
    image: semitechnologies/weaviate:${WEAVIATE_VERSION}
    container_name: ai-weaviate
    environment:
      QUERY_DEFAULTS_LIMIT: 25
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: 'true'
      PERSISTENCE_DATA_PATH: '/var/lib/weaviate'
      DEFAULT_VECTORIZER_MODULE: 'none'
      ENABLE_MODULES: ''
      CLUSTER_HOSTNAME: 'node1'
    ports:
      - "${WEAVIATE_PORT}:8080"
      - "${WEAVIATE_GRPC_PORT}:50051"
    volumes:
      - ../../data/weaviate:/var/lib/weaviate
    networks:
      - ai-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/v1/.well-known/ready"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF
        log_success "Weaviate stack configuration generated"
    fi
    
    # ========================================================================
    # QDRANT STACK
    # ========================================================================
    if [[ "${ENABLE_QDRANT}" == "true" ]]; then
        cat > "${PROJECT_ROOT}/stacks/qdrant/docker-compose.yml" << 'EOF'
networks:
  ai-network:
    external: true

services:
  qdrant:
    image: qdrant/qdrant:${QDRANT_VERSION}
    container_name: ai-qdrant
    environment:
      QDRANT__SERVICE__API_KEY: ${QDRANT_API_KEY}
    ports:
      - "${QDRANT_PORT}:6333"
      - "${QDRANT_GRPC_PORT}:6334"
    volumes:
      - ../../data/qdrant:/qdrant/storage
    networks:
      - ai-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6333/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF
        log_success "Qdrant stack configuration generated"
    fi
    
    # ========================================================================
    # DIFY STACK
    # ========================================================================
    if [[ "${ENABLE_DIFY}" == "true" ]]; then
        cat > "${PROJECT_ROOT}/stacks/dify/docker-compose.yml" << 'EOF'
networks:
  ai-network:
    external: true

services:
  dify-api:
    image: langgenius/dify-api:${DIFY_VERSION}
    container_name: ai-dify-api
    environment:
      MODE: api
      SECRET_KEY: ${DIFY_SECRET_KEY}
      DB_USERNAME: ${POSTGRES_USER}
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_HOST: ai-postgres
      DB_PORT: 5432
      DB_DATABASE: ${DIFY_DB_NAME}
      REDIS_HOST: ai-redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      STORAGE_TYPE: s3
      S3_ENDPOINT: http://ai-minio:9000
      S3_ACCESS_KEY: ${MINIO_ROOT_USER}
      S3_SECRET_KEY: ${MINIO_ROOT_PASSWORD}
      S3_BUCKET_NAME: dify
    ports:
      - "${DIFY_API_PORT}:5001"
    volumes:
      - ../../data/dify:/app/api/storage
    networks:
      - ai-network
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

  dify-worker:
    image: langgenius/dify-api:${DIFY_VERSION}
    container_name: ai-dify-worker
    environment:
      MODE: worker
      SECRET_KEY: ${DIFY_SECRET_KEY}
      DB_USERNAME: ${POSTGRES_USER}
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_HOST: ai-postgres
      DB_PORT: 5432
      DB_DATABASE: ${DIFY_DB_NAME}
      REDIS_HOST: ai-redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      STORAGE_TYPE: s3
      S3_ENDPOINT: http://ai-minio:9000
      S3_ACCESS_KEY: ${MINIO_ROOT_USER}
      S3_SECRET_KEY: ${MINIO_ROOT_PASSWORD}
      S3_BUCKET_NAME: dify
    networks:
      - ai-network
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

  dify-web:
    image: langgenius/dify-web:${DIFY_VERSION}
    container_name: ai-dify-web
    environment:
      CONSOLE_API_URL: http://${DOMAIN}:${DIFY_API_PORT}
      APP_API_URL: http://${DOMAIN}:${DIFY_API_PORT}
    ports:
      - "${DIFY_PORT}:3000"
    networks:
      - ai-network
    restart: unless-stopped
    depends_on:
      - dify-api
EOF
        log_success "Dify stack configuration generated"
    fi
    
    # ========================================================================
    # N8N STACK
    # ========================================================================
    if [[ "${ENABLE_N8N}" == "true" ]]; then
        cat > "${PROJECT_ROOT}/stacks/n8n/docker-compose.yml" << 'EOF'
networks:
  ai-network:
    external: true

services:
  n8n:
    image: n8nio/n8n:${N8N_VERSION}
    container_name: ai-n8n
    environment:
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: ai-postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: ${N8N_DB_NAME}
      DB_POSTGRESDB_USER: ${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}
      N8N_HOST: ${DOMAIN}
      N8N_PORT: 5678
      N8N_PROTOCOL: http
      WEBHOOK_URL: http://${DOMAIN}/n8n/
    ports:
      - "${N8N_PORT}:5678"
    volumes:
      - ../../data/n8n:/home/node/.n8n
    networks:
      - ai-network
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
EOF
        log_success "n8n stack configuration generated"
    fi
    
    # ========================================================================
    # ANYTHINGLLM STACK
    # ========================================================================
    if [[ "${ENABLE_ANYTHINGLLM}" == "true" ]]; then
        cat > "${PROJECT_ROOT}/stacks/anythingllm/docker-compose.yml" << 'EOF'
networks:
  ai-network:
    external: true

services:
  anythingllm:
    image: mintplexlabs/anythingllm:${ANYTHINGLLM_VERSION}
    container_name: ai-anythingllm
    environment:
      JWT_SECRET: ${ANYTHINGLLM_JWT_SECRET}
      STORAGE_DIR: /app/server/storage
    ports:
      - "${ANYTHINGLLM_PORT}:3001"
    volumes:
      - ../../data/anythingllm:/app/server/storage
    networks:
      - ai-network
    restart: unless-stopped
EOF
        log_success "AnythingLLM stack configuration generated"
    fi
    
    # ========================================================================
    # FLOWISE STACK
    # ========================================================================
    if [[ "${ENABLE_FLOWISE}" == "true" ]]; then
        cat > "${PROJECT_ROOT}/stacks/flowise/docker-compose.yml" << 'EOF'
networks:
  ai-network:
    external: true

services:
  flowise:
    image: flowiseai/flowise:${FLOWISE_VERSION}
    container_name: ai-flowise
    environment:
      FLOWISE_USERNAME: ${FLOWISE_USERNAME}
      FLOWISE_PASSWORD: ${FLOWISE_PASSWORD}
      FLOWISE_SECRETKEY_OVERWRITE: ${FLOWISE_SECRETKEY}
      DATABASE_TYPE: postgres
      DATABASE_HOST: ai-postgres
      DATABASE_PORT: 5432
      DATABASE_NAME: ${POSTGRES_DB}
      DATABASE_USER: ${POSTGRES_USER}
      DATABASE_PASSWORD: ${POSTGRES_PASSWORD}
    ports:
      - "${FLOWISE_PORT}:3000"
    volumes:
      - ../../data/flowise:/root/.flowise
    networks:
      - ai-network
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
EOF
        log_success "Flowise stack configuration generated"
    fi
    
    log_success "All stack configurations generated (Docker Compose v2 format)"
}

# ============================================================================
# DEPLOY INFRASTRUCTURE
# ============================================================================
deploy_infrastructure() {
    log_step "8/12" "Deploying infrastructure services"
    
    log_info "Starting infrastructure stack..."
    cd "${PROJECT_ROOT}/stacks/infrastructure"
    docker compose up -d
    
    log_info "Waiting for services to be healthy..."
    sleep 10
    
    # Check PostgreSQL
    if docker exec ai-postgres pg_isready -U "${POSTGRES_USER}" &>/dev/null; then
        log_success "PostgreSQL is ready"
    else
        log_warning "PostgreSQL may need more time to start"
    fi
    
    # Check Redis
    if docker exec ai-redis redis-cli ping &>/dev/null; then
        log_success "Redis is ready"
    else
        log_warning "Redis may need more time to start"
    fi
    
    log_success "Infrastructure deployed"
}

# ============================================================================
# INITIALIZE DATABASES
# ============================================================================
initialize_databases() {
    log_step "9/12" "Initializing databases"
    
    log_info "Creating databases for services..."
    
    # Create Dify database
    if [[ "${ENABLE_DIFY}" == "true" ]]; then
        docker exec ai-postgres psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c "CREATE DATABASE ${DIFY_DB_NAME};" 2>/dev/null || log_info "Dify database already exists"
        log_success "Dify database ready"
    fi
    
    # Create n8n database
    if [[ "${ENABLE_N8N}" == "true" ]]; then
        docker exec ai-postgres psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c "CREATE DATABASE ${N8N_DB_NAME};" 2>/dev/null || log_info "n8n database already exists"
        log_success "n8n database ready"
    fi
    
    # Create MinIO buckets
    log_info "Creating MinIO buckets..."
    sleep 5
    docker exec ai-minio mc alias set myminio http://localhost:9000 "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" 2>/dev/null || true
    docker exec ai-minio mc mb myminio/dify 2>/dev/null || log_info "Dify bucket already exists"
    docker exec ai-minio mc mb myminio/n8n 2>/dev/null || log_info "n8n bucket already exists"
    
    log_success "Databases initialized"
}

# ============================================================================
# SHOW SUMMARY
# ============================================================================
show_summary() {
    log_step "10/12" "Setup Summary"
    
    cat << EOF

${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✓ SETUP COMPLETE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

${CYAN}Enabled Services:${NC}
EOF

    [[ "${ENABLE_OLLAMA}" == "true" ]] && echo "  ✓ Ollama (Local LLMs)"
    [[ "${ENABLE_LITELLM}" == "true" ]] && echo "  ✓ LiteLLM (LLM Gateway)"
    [[ "${ENABLE_WEAVIATE}" == "true" ]] && echo "  ✓ Weaviate (Vector DB)"
    [[ "${ENABLE_QDRANT}" == "true" ]] && echo "  ✓ Qdrant (Vector DB)"
    [[ "${ENABLE_DIFY}" == "true" ]] && echo "  ✓ Dify (LLM Platform)"
    [[ "${ENABLE_N8N}" == "true" ]] && echo "  ✓ n8n (Workflow Automation)"
    [[ "${ENABLE_ANYTHINGLLM}" == "true" ]] && echo "  ✓ AnythingLLM (Document Chat)"
    [[ "${ENABLE_FLOWISE}" == "true" ]] && echo "  ✓ Flowise (Visual AI Builder)"

    cat << EOF

${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🚀 NEXT STEPS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

${YELLOW}1. Start All Services:${NC}
   cd ${PROJECT_ROOT}
   ./scripts/2-start-services.sh start

${YELLOW}2. Check Service Status:${NC}
   ./scripts/2-start-services.sh status

${YELLOW}3. Access Services:${NC}
   Domain: http://${DOMAIN}

${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🔐 IMPORTANT CREDENTIALS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

${RED}⚠️  Credentials saved in: ${PROJECT_ROOT}/.env${NC}

${YELLOW}PostgreSQL:${NC}
  User: ${POSTGRES_USER}
  Database: ${POSTGRES_DB}
  Port: ${POSTGRES_PORT}

${YELLOW}MinIO:${NC}
  Console: http://${DOMAIN}:${MINIO_CONSOLE_PORT}
  User: ${MINIO_ROOT_USER}

${YELLOW}Flowise:${NC}
  Username: ${FLOWISE_USERNAME}

EOF
}

# ============================================================================
# SAVE QUICK REFERENCE
# ============================================================================
save_quick_reference() {
    log_step "11/12" "Creating quick reference guide"
    
    cat > "${PROJECT_ROOT}/QUICK_START.md" << EOF
# AI Platform - Quick Reference Guide

## 🚀 Quick Start

\`\`\`bash
# Start all services
./scripts/2-start-services.sh start

# Check status
./scripts/2-start-services.sh status
\`\`\`

## 🌐 Service URLs

- **Domain**: http://${DOMAIN}
- **Dify**: http://${DOMAIN}:${DIFY_PORT}
- **n8n**: http://${DOMAIN}:${N8N_PORT}
- **MinIO Console**: http://${DOMAIN}:${MINIO_CONSOLE_PORT}

## 🔐 Credentials

All credentials saved in: \`.env\`

---
**Setup Date**: $(date)
**Log File**: ${LOGFILE}
EOF

    log_success "Quick reference saved to QUICK_START.md"
}

# ============================================================================
# VERIFY SETUP
# ============================================================================
verify_setup() {
    log_step "12/12" "Verifying setup"
    
    local errors=0
    
    # Check .env file
    if [[ -f "${PROJECT_ROOT}/.env" ]]; then
        log_success ".env file exists"
    else
        log_error ".env file missing"
        ((errors++))
    fi
    
    # Check Docker network
    if docker network inspect ai-network &>/dev/null; then
        log_success "Docker network exists"
    else
        log_error "Docker network missing"
        ((errors++))
    fi
    
    # Check infrastructure containers
    if docker ps --filter "name=ai-postgres" --format "{{.Names}}" | grep -q "ai-postgres"; then
        log_success "PostgreSQL container running"
    else
        log_warning "PostgreSQL container not running"
        ((errors++))
    fi
    
    if docker ps --filter "name=ai-redis" --format "{{.Names}}" | grep -q "ai-redis"; then
        log_success "Redis container running"
    else
        log_warning "Redis container not running"
        ((errors++))
    fi
    
    if docker ps --filter "name=ai-minio" --format "{{.Names}}" | grep -q "ai-minio"; then
        log_success "MinIO container running"
    else
        log_warning "MinIO container not running"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "Setup verification passed!"
    else
        log_warning "Setup completed with ${errors} warning(s)"
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
main() {
    show_banner
    check_prerequisites
    set_default_values
    collect_configuration
    create_directories
    save_credentials
    create_docker_network
    generate_stack_configs
    deploy_infrastructure
    initialize_databases
    show_summary
    save_quick_reference
    verify_setup
    
    echo ""
    log_success "Setup complete! Check ${LOGFILE} for details."
    log_info "Next: Run ./scripts/2-start-services.sh start"
    echo ""
}

# Run main function
main "$@"
