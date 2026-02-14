#!/bin/bash

#==============================================================================
# Script 1: System Setup & Configuration Collection (Refactored)
# Purpose: Complete system preparation with proper Docker setup
# Version: 5.0.0 (Refactored)
#==============================================================================

set -euo pipefail

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# Paths
readonly DATA_ROOT="/mnt/data"
readonly METADATA_DIR="$DATA_ROOT/metadata"
readonly STATE_FILE="$METADATA_DIR/setup_state.json"
readonly LOG_FILE="$DATA_ROOT/logs/setup.log"
readonly ENV_FILE="$DATA_ROOT/.env"
readonly SERVICES_FILE="$METADATA_DIR/selected_services.json"
readonly COMPOSE_DIR="$DATA_ROOT/compose"

# UI Functions
print_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════════════╗"
    echo "║            AI PLATFORM AUTOMATION - SETUP                      ║"
    echo "║                      Version 5.0.0 (Refactored)              ║"
    echo "║                System Setup & Docker Configuration        ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

print_header() {
    local title="$1"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $title"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_phase() {
    local phase="$1"
    local icon="$2"
    local title="$3"
    echo ""
    print_header "$icon STEP $phase: $title"
}

# Input functions
prompt_input() {
    local var_name="$1"
    local prompt_text="$2"
    local default_value="${3:-}"
    local is_sensitive="${4:-false}"
    
    if [[ "$is_sensitive" == "true" ]]; then
        echo -n -e "${YELLOW}$prompt_text: ${NC}"
        read -s INPUT_RESULT
    else
        echo -n -e "${YELLOW}$prompt_text [${GREEN}$default_value${NC}]: ${NC}"
        read -r INPUT_RESULT
    fi
    
    if [[ -n "$INPUT_RESULT" ]]; then
        echo "$var_name=$INPUT_RESULT" >> "$ENV_FILE"
    else
        echo "$var_name=$default_value" >> "$ENV_FILE"
    fi
}

confirm() {
    local message="$1"
    local default="${2:-n}"
    echo -n -e "${YELLOW}$message [${GREEN}$default${NC}]: ${NC}"
    read -r response
    [[ "$response" =~ ^[Yy]$ ]]
}

# Docker Setup
install_docker() {
    log_phase "1" "🐳" "Docker Installation"
    
    if command -v docker >/dev/null 2>&1; then
        print_success "Docker already installed"
        docker --version
        return 0
    fi
    
    print_info "Installing Docker..."
    apt update -qq
    apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
    
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt update -qq
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    systemctl start docker
    systemctl enable docker
    
    # Add user to docker group
    usermod -aG docker "${SUDO_USER:-$USER}"
    
    docker --version
    print_success "Docker installed successfully"
}

configure_docker() {
    log_phase "2" "⚙️" "Docker Configuration"
    
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "5"
    },
    "storage-driver": "overlay2",
    "exec-opts": ["native.cgroupdriver=systemd"]
}
EOF
    
    systemctl restart docker
    
    # Create consistent networks
    print_info "Creating Docker networks..."
    docker network create ai_platform 2>/dev/null || true
    docker network create ai_platform_internal 2>/dev/null || true
    docker network create ai_platform_monitoring 2>/dev/null || true
    
    print_success "Docker configured successfully"
}

# Environment Setup
setup_environment() {
    log_phase "3" "🌍" "Environment Configuration"
    
    # Create directories
    mkdir -p "$DATA_ROOT"/{compose,logs,config,data,env}
    mkdir -p "$METADATA_DIR"
    
    # Initialize environment file with proper variable names
    if [[ ! -f "$ENV_FILE" ]]; then
        cat > "$ENV_FILE" <<'EOF'
# AI Platform Environment
# Generated: $(date -I)

# System Configuration
DATA_ROOT=/mnt/data
METADATA_DIR=/mnt/data/metadata
TIMEZONE=UTC
LOG_LEVEL=info

# Network Configuration
DOMAIN=ai.datasquiz.net
DOMAIN_NAME=ai.datasquiz.net
DOMAIN_RESOLVES=true
PUBLIC_IP=
PROXY_CONFIG_METHOD=direct
PROXY_TYPE=none
SSL_TYPE=none
SSL_EMAIL=

# Service Ports
PROMETHEUS_PORT=9090
GRAFANA_PORT=3001
N8N_PORT=5678
OLLAMA_PORT=11434
OPENCLAW_PORT=18789
DIFY_PORT=8080
ANYTHINGLLM_PORT=3001
LITELLM_PORT=4000
REDIS_PORT=6379
POSTGRES_PORT=5432
TAILSCALE_PORT=8443
OPENWEBUI_PORT=3000
SIGNAL_API_PORT=8090
MINIO_PORT=9000

# Database Configuration
POSTGRES_DB=aiplatform
POSTGRES_USER=ds-admin
POSTGRES_PASSWORD=
REDIS_USER=ds-admin
REDIS_PASSWORD=

# Vector Database
VECTOR_DB_TYPE=none

# LLM Configuration
OLLAMA_DEFAULT_MODEL=llama3.2:8b
OLLAMA_MODELS=
LLM_PROVIDERS=local
LITELLM_ROUTING_STRATEGY=local-first
LITELLM_MASTER_KEY=
LITELLM_CACHE_ENABLED=true
LITELLM_CACHE_TTL=3600
LITELLM_RATE_LIMIT_ENABLED=true
LITELLM_RATE_LIMIT_REQUESTS_PER_MINUTE=60

# Security Configuration
ADMIN_PASSWORD=
JWT_SECRET=
N8N_ENCRYPTION_KEY=

# Service-specific Configuration
SIGNAL_PHONE=
SIGNAL_PAIRING_METHOD=internal_api
SIGNAL_API_PAIRING_URL=http://localhost:8081/v1/generate_token
SIGNAL_WEBHOOK_URL=http://signal-api:8090/v2/receive

OPENCLAW_ADMIN_USER=ds-admin
OPENCLAW_ADMIN_PASSWORD=
OPENCLAW_WEBSEARCH=both
OPENCLAW_ENABLE_SIGNAL=true
OPENCLAW_ENABLE_LITELM=true
OPENCLAW_ENABLE_N8N=true

# Monitoring Configuration
GRAFANA_PASSWORD=

# Storage Configuration
MINIO_ROOT_USER=ds-admin
MINIO_ROOT_PASSWORD=

# Get service category
        echo ""
        print_header "🤖 Ollama Model Selection"
        echo ""
        
        print_info "Select models to download and use:"
        echo ""
        echo "Recommended Models:"
        echo "  [1] llama3.2:8b (7.8GB) - Latest Llama 3.2"
        echo "  [2] llama3.2:70b (43GB) - Full Llama 3.2 (requires 64GB RAM)"
        echo "  [3] mistral:7b (4.7GB) - Mistral 7B"
        echo "  [4] codellama:13b (7.6GB) - Code Llama"
        echo ""
        echo "Specialized Models:"
        echo "  [5] llama3.1:8b (4.9GB) - Llama 3.1"
        echo "  [6] mixtral:8x7b (4.7GB) - Mixtral MoE"
        echo "  [7] deepseek-coder:6.7b (3.8GB) - DeepSeek Coder"
        echo ""
        echo "Select models (space-separated, e.g., '1 3 5'):"
        echo "Or enter 'recommended' for models 1,3,4"
        echo ""
        
        while true; do
            echo -n -e "${YELLOW}Select models:${NC} "
            read -r model_selection
            
            if [[ "$model_selection" == "recommended" ]]; then
                model_selection="1 3 4"
                print_info "Selected recommended models: llama3.2:8b, mistral:7b, codellama:13b"
            fi
            
            if [[ -n "$model_selection" ]]; then
                local models_array=($model_selection)
                local valid_models=true
                
                for model_num in "${models_array[@]}"; do
                    case "$model_num" in
                        1|2|3|4|5|6|7) 
                            # Valid model selection
                            ;;
                        *) 
                            print_error "Invalid model selection: $model_num"
                            valid_models=false
                            break
                            ;;
                    esac
                done
                
                if [[ "$valid_models" == "true" ]]; then
                    local model_list=""
                    for model_num in "${models_array[@]}"; do
                        case "$model_num" in
                            1) model_list="${model_list}llama3.2:8b " ;;
                            2) model_list="${model_list}llama3.2:70b " ;;
                            3) model_list="${model_list}mistral:7b " ;;
                            4) model_list="${model_list}codellama:13b " ;;
                            5) model_list="${model_list}llama3.1:8b " ;;
                            6) model_list="${model_list}mixtral:8x7b " ;;
                            7) model_list="${model_list}deepseek-coder:6.7b " ;;
                        esac
                    done
                    
                    # Remove trailing space and save
                    model_list=${model_list% }
                    echo "OLLAMA_MODELS=$model_list" >> "$ENV_FILE"
                    
                    # Set default model to first selected model
                    local first_model=${models_array[0]}
                    case "$first_model" in
                        1) echo "OLLAMA_DEFAULT_MODEL=llama3.2:8b" >> "$ENV_FILE" ;;
                        2) echo "OLLAMA_DEFAULT_MODEL=llama3.2:70b" >> "$ENV_FILE" ;;
                        3) echo "OLLAMA_DEFAULT_MODEL=mistral:7b" >> "$ENV_FILE" ;;
                        4) echo "OLLAMA_DEFAULT_MODEL=codellama:13b" >> "$ENV_FILE" ;;
                        5) echo "OLLAMA_DEFAULT_MODEL=llama3.1:8b" >> "$ENV_FILE" ;;
                        6) echo "OLLAMA_DEFAULT_MODEL=mixtral:8x7b" >> "$ENV_FILE" ;;
                        7) echo "OLLAMA_DEFAULT_MODEL=deepseek-coder:6.7b" >> "$ENV_FILE" ;;
                    esac
                    
                    print_success "Ollama models configured: $model_list"
                    break
                fi
            
            if [[ "$valid_models" == "true" ]]; then
                break
            fi
        done
    fi
}

get_service_category() {
    local service="$1"
    case "$service" in
        postgres|redis|tailscale) echo "infrastructure" ;;
        openwebui|anythingllm|dify|n8n|flowise|ollama) echo "ai_application" ;;
        grafana|prometheus) echo "monitoring" ;;
        signal-api) echo "communication" ;;
        minio) echo "storage" ;;
        qdrant|weaviate|milvus|chroma) echo "vector_database" ;;
        caddy|traefik|nginx-proxy-manager|swag) echo "proxy" ;;
        *) echo "other" ;;
    esac
}

# Configuration Collection
collect_configurations() {
    log_phase "5" "⚙️" "Configuration Collection"
    
    # Database Configuration
    echo ""
    print_info "Database Configuration"
    prompt_input "POSTGRES_USER" "PostgreSQL admin user" "ds-admin"
    prompt_input "POSTGRES_PASSWORD" "PostgreSQL admin password" "" true
    prompt_input "REDIS_USER" "Redis admin user" "ds-admin"
    prompt_input "REDIS_PASSWORD" "Redis admin password" "" true
    
    # LLM Configuration
    echo ""
    print_info "LLM Configuration"
    prompt_input "OLLAMA_DEFAULT_MODEL" "Default Ollama model" "llama3.2:8b"
    prompt_input "LITELLM_MASTER_KEY" "LiteLLM master key" "" true
    
    # Security Configuration
    echo ""
    print_info "Security Configuration"
    prompt_input "ADMIN_PASSWORD" "Admin password" "" true
    prompt_input "JWT_SECRET" "JWT secret" "" true
    
    # Service-specific configurations
    echo ""
    print_info "Service-specific Configuration"
    
    # Signal API
    if [[ -n "$(jq -r '.services[] | select(.key=="signal-api") | .key' "$SERVICES_FILE" 2>/dev/null)" ]]; then
        prompt_input "SIGNAL_PHONE" "Signal phone number" "" false
        echo "SIGNAL_PHONE=$INPUT_RESULT" >> "$ENV_FILE"
    fi
    
    # OpenClaw
    if [[ -n "$(jq -r '.services[] | select(.key=="openclaw") | .key' "$SERVICES_FILE" 2>/dev/null)" ]]; then
        prompt_input "OPENCLAW_ADMIN_USER" "OpenClaw admin user" "ds-admin"
        prompt_input "OPENCLAW_ADMIN_PASSWORD" "OpenClaw admin password" "" true
    fi
    
    # MinIO
    if [[ -n "$(jq -r '.services[] | select(.key=="minio") | .key' "$SERVICES_FILE" 2>/dev/null)" ]]; then
        prompt_input "MINIO_ROOT_USER" "MinIO root user" "ds-admin"
        prompt_input "MINIO_ROOT_PASSWORD" "MinIO root password" "" true
    fi
    
    print_success "Configuration collection completed"
}

# Generate Base Docker Compose Files
generate_base_compose_files() {
    log_phase "6" "📝" "Base Docker Compose Generation"
    
    mkdir -p "$COMPOSE_DIR"
    
    # Generate infrastructure compose file
    cat > "$COMPOSE_DIR/infrastructure.yml" <<EOF
version: '3.8'

networks:
  ai_platform:
    external: true
  ai_platform_internal:
    external: true

services:
  postgres:
    image: postgres:15-alpine
    container_name: postgres
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    networks:
      - ai_platform
    environment:
      - POSTGRES_USER=\${POSTGRES_USER:-ds-admin}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_DB=\${POSTGRES_DB:-aiplatform}
      - PGDATA=/var/lib/postgresql/data/pgdata
    volumes:
      - \${DATA_ROOT}/postgres:/var/lib/postgresql/data
    ports:
      - "127.0.0.1:\${POSTGRES_PORT:-5432}:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER:-ds-admin} -d \${POSTGRES_DB:-aiplatform}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  redis:
    image: redis:7-alpine
    container_name: redis
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    networks:
      - ai_platform
    command: redis-server --appendonly yes --requirepass \${REDIS_PASSWORD}
    volumes:
      - \${DATA_ROOT}/redis:/data
    ports:
      - "\${REDIS_PORT:-6379}:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
EOF
    
    # Generate vector database compose files based on selection
    local vector_db_type=$(grep "^VECTOR_DB_TYPE=" "$ENV_FILE" | cut -d'=' -f2)
    case "$vector_db_type" in
        qdrant)
            cat > "$COMPOSE_DIR/qdrant.yml" <<EOF
version: '3.8'

networks:
  ai_platform:
    external: true

services:
  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    networks:
      - ai_platform
    ports:
      - "6333:6333"
    volumes:
      - \${DATA_ROOT}/qdrant:/qdrant/storage
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6333/health"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF
            ;;
        weaviate)
            cat > "$COMPOSE_DIR/weaviate.yml" <<EOF
version: '3.8'

networks:
  ai_platform:
    external: true

services:
  weaviate:
    image: semitechnologies/weaviate:latest
    container_name: weaviate
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    networks:
      - ai_platform
    ports:
      - "8080:8080"
    environment:
      - AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: 'true'
      - PERSISTENCE_DATA_PATH: /var/lib/weaviate
    volumes:
      - \${DATA_ROOT}/weaviate:/var/lib/weaviate
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/v1/.well-known/ready"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF
            ;;
    esac
    
    print_success "Base Docker Compose files generated"
}

# Save setup state
save_setup_state() {
    cat > "$STATE_FILE" <<EOF
{
    "status": "success",
    "timestamp": "$(date -I)",
    "version": "5.0.0",
    "networks_created": true,
    "compose_files_generated": true,
    "environment_configured": true
}
EOF
}

# Main execution
main() {
    print_banner
    
    # Phase 1: Docker Installation
    install_docker
    
    # Phase 2: Docker Configuration
    configure_docker
    
    # Phase 3: Environment Setup
    setup_environment
    
    # Phase 4: Service Selection
    select_services
    
    # Phase 5: Configuration Collection
    collect_configurations
    
    # Phase 6: Generate Base Compose Files
    generate_base_compose_files
    
    # Save state
    save_setup_state
    
    print_success "Setup completed successfully!"
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo "  1. Run: ${YELLOW}sudo bash 0-complete-cleanup.sh${NC}"
    echo "  2. Run: ${YELLOW}sudo bash 2-deploy-services.sh${NC}"
    echo ""
}

# Execute main function
main "$@"
