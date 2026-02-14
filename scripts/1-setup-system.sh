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

# Proxy Configuration
EOF
        print_success "Environment file initialized"
    else
        print_info "Environment file exists - updating variables"
    fi
}

# Generate random password
generate_random_password() {
    local length="${1:-24}"
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
}

# Get service category
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
    
    # Read selected services from JSON file
    local final_services=()
    while IFS= read -r service; do
        final_services+=("$service")
    done < <(jq -r '.services[].key' "$SERVICES_FILE" 2>/dev/null)
    
    # Database Configuration
    echo ""
    print_info "Database Configuration"
    
    # PostgreSQL configuration
    if [[ " ${final_services[*]} " =~ " postgres " ]]; then
        local postgres_password=$(generate_random_password 24)
        echo "POSTGRES_PASSWORD=$postgres_password" >> "$ENV_FILE"
        print_success "PostgreSQL configuration generated"
    fi
    
    # Redis configuration
    if [[ " ${final_services[*]} " =~ " redis " ]]; then
        local redis_password=$(generate_random_password 24)
        echo "REDIS_PASSWORD=$redis_password" >> "$ENV_FILE"
        print_success "Redis configuration generated"
    fi
    
    # Ollama model selection
    if [[ " ${final_services[*]} " =~ " ollama " ]]; then
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
        echo "  [5] qwen2.5:14b (8.2GB) - Qwen 2.5"
        echo ""
        echo "Specialized Models:"
        echo "  [6] llama3.1:8b (4.9GB) - Llama 3.1"
        echo "  [7] mixtral:8x7b (4.7GB) - Mixtral MoE"
        echo "  [8] deepseek-coder:6.7b (3.8GB) - DeepSeek Coder"
        echo ""
        echo "Select models (space-separated, e.g., '1 3 5'):"
        echo "Or enter 'recommended' for models 1,3,4"
        echo ""
        
        while true; do
            echo -n -e "${YELLOW}Enter model selection:${NC} "
            read -r model_selection
            
            if [[ "$model_selection" == "recommended" ]]; then
                echo "OLLAMA_MODELS=llama3.2:8b,mistral:7b,codellama:13b" >> "$ENV_FILE"
                print_success "Recommended models selected: llama3.2:8b, mistral:7b, codellama:13b"
                break
            elif [[ "$model_selection" =~ ^[0-9\ ]+$ ]]; then
                local selected_models=()
                for num in $model_selection; do
                    case $num in
                        1) selected_models+=("llama3.2:8b") ;;
                        2) selected_models+=("llama3.2:70b") ;;
                        3) selected_models+=("mistral:7b") ;;
                        4) selected_models+=("codellama:13b") ;;
                        5) selected_models+=("qwen2.5:14b") ;;
                        6) selected_models+=("llama3.1:8b") ;;
                        7) selected_models+=("mixtral:8x7b") ;;
                        8) selected_models+=("deepseek-coder:6.7b") ;;
                        *) print_warn "Invalid model selection: $num" ;;
                    esac
                done
                
                if [[ ${#selected_models[@]} -gt 0 ]]; then
                    local models_str=$(IFS=','; echo "${selected_models[*]}")
                    echo "OLLAMA_MODELS=$models_str" >> "$ENV_FILE"
                    print_success "Models selected: $models_str"
                    break
                fi
            else
                print_error "Invalid selection. Please enter numbers or 'recommended'"
            fi
        done
    fi
    
    # LLM Configuration
    echo ""
    print_info "LLM Configuration"
    echo "OLLAMA_DEFAULT_MODEL=llama3.2:8b" >> "$ENV_FILE"
    
    # LiteLLM configuration
    if [[ " ${final_services[*]} " =~ " litellm " ]]; then
        local litellm_master_key=$(generate_random_password 32)
        echo "LITELLM_MASTER_KEY=$litellm_master_key" >> "$ENV_FILE"
        echo "LITELLM_CACHE_ENABLED=true" >> "$ENV_FILE"
        echo "LITELLM_CACHE_TTL=3600" >> "$ENV_FILE"
        echo "LITELLM_RATE_LIMIT_ENABLED=true" >> "$ENV_FILE"
        echo "LITELLM_RATE_LIMIT_REQUESTS_PER_MINUTE=60" >> "$ENV_FILE"
        print_success "LiteLLM configuration completed"
    fi
    
    # Security Configuration
    echo ""
    print_info "Security Configuration"
    
    # Admin passwords
    local admin_password=$(generate_random_password 24)
    echo "ADMIN_PASSWORD=$admin_password" >> "$ENV_FILE"
    echo "GRAFANA_PASSWORD=$admin_password" >> "$ENV_FILE"
    
    # JWT secrets
    local jwt_secret=$(generate_random_password 64)
    echo "JWT_SECRET=$jwt_secret" >> "$ENV_FILE"
    
    # n8n encryption key
    if [[ " ${final_services[*]} " =~ " n8n " ]]; then
        local n8n_key=$(generate_random_password 64)
        echo "N8N_ENCRYPTION_KEY=$n8n_key" >> "$ENV_FILE"
    fi
    
    # Service-specific configurations
    echo ""
    print_info "Service-specific Configuration"
    
    # Signal API
    if [[ -n "$(jq -r '.services[] | select(.key=="signal-api") | .key' "$SERVICES_FILE" 2>/dev/null)" ]]; then
        echo ""
        print_header "📱 Signal API Configuration"
        echo ""
        
        print_info "Signal Bot Configuration"
        echo ""
        
        prompt_input "SIGNAL_PHONE" "Signal phone number (E.164 format, e.g., +15551234567)" "" false
        echo "SIGNAL_PHONE=$INPUT_RESULT" >> "$ENV_FILE"
        
        echo "SIGNAL_WEBHOOK_URL=http://signal-api:8090/v2/receive" >> "$ENV_FILE"
        echo "SIGNAL_API_PORT=8090" >> "$ENV_FILE"
        
        print_success "Signal API configuration completed"
    fi
    
    # OpenClaw
    if [[ -n "$(jq -r '.services[] | select(.key=="openclaw") | .key' "$SERVICES_FILE" 2>/dev/null)" ]]; then
        echo ""
        print_header "🔧 OpenClaw Configuration"
        echo ""
        
        echo "OPENCLAW_ADMIN_USER=admin" >> "$ENV_FILE"
        local openclaw_password=$(generate_random_password 24)
        echo "OPENCLAW_ADMIN_PASSWORD=$openclaw_password" >> "$ENV_FILE"
        
        # Web Search Configuration
        echo ""
        print_info "Web Search Configuration"
        echo ""
        echo "Select web search provider for OpenClaw:"
        echo "  1) Brave Search API (Recommended)"
        echo "  2) SerpApi (Google Search)"
        echo "  3) Both Brave and SerpApi"
        echo "  4) None (Disable web search)"
        echo ""
        
        while true; do
            echo -n -e "${YELLOW}Select web search provider [1-4]:${NC} "
            read -r websearch_choice
            
            case "$websearch_choice" in
                1)
                    echo "OPENCLAW_WEBSEARCH=brave" >> "$ENV_FILE"
                    prompt_input "BRAVE_API_KEY" "Brave Search API key" "" false
                    break
                    ;;
                2)
                    echo "OPENCLAW_WEBSEARCH=serpapi" >> "$ENV_FILE"
                    prompt_input "SERPAPI_KEY" "SerpApi key" "" false
                    break
                    ;;
                3)
                    echo "OPENCLAW_WEBSEARCH=both" >> "$ENV_FILE"
                    prompt_input "BRAVE_API_KEY" "Brave Search API key" "" false
                    prompt_input "SERPAPI_KEY" "SerpApi key" "" false
                    break
                    ;;
                4)
                    echo "OPENCLAW_WEBSEARCH=none" >> "$ENV_FILE"
                    break
                    ;;
                *)
                    print_error "Invalid selection"
                    ;;
            esac
        done
        
        print_success "OpenClaw configuration completed"
    fi
    
    # MinIO
    if [[ -n "$(jq -r '.services[] | select(.key=="minio") | .key' "$SERVICES_FILE" 2>/dev/null)" ]]; then
        echo ""
        print_info "MinIO Configuration"
        echo ""
        
        echo "MINIO_ROOT_USER=minioadmin" >> "$ENV_FILE"
        local minio_pass=$(generate_random_password 32)
        echo "MINIO_ROOT_PASSWORD=$minio_pass" >> "$ENV_FILE"
        
        print_success "MinIO configuration completed"
    fi
    
    print_success "Configuration collection completed"
}

# Generate Base Docker Compose Files
generate_base_compose_files() {
    log_phase "6" "📝" "Base Docker Compose Generation"
    
    mkdir -p "$COMPOSE_DIR"
    
    # Generate infrastructure compose file
    echo "version: '3.8'" > "$COMPOSE_DIR/infrastructure.yml"
    echo "" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "networks:" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "  ai_platform:" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "    external: true" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "  ai_platform_internal:" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "    external: true" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "services:" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "  postgres:" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "    image: postgres:15-alpine" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "    container_name: postgres" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "    restart: unless-stopped" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "    security_opt:" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "      - no-new-privileges:true" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "    networks:" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "      - ai_platform" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "    environment:" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "      - POSTGRES_USER=\${POSTGRES_USER:-ds-admin}" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "      - POSTGRES_DB=\${POSTGRES_DB:-aiplatform}" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "      - PGDATA=/var/lib/postgresql/data/pgdata" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "    volumes:" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "      - \${DATA_ROOT}/postgres:/var/lib/postgresql/data" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "    ports:" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "      - \"127.0.0.1:\${POSTGRES_PORT:-5432}:5432\"" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "    healthcheck:" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "      test: [\"CMD-SHELL\", \"pg_isready -U \${POSTGRES_USER:-ds-admin} -d \${POSTGRES_DB:-aiplatform}\"]" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "      interval: 10s" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "      timeout: 5s" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "      retries: 5" >> "$COMPOSE_DIR/infrastructure.yml"
    echo "      start_period: 30s" >> "$COMPOSE_DIR/infrastructure.yml"
    
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

# Service Selection
select_services() {
    log_phase "4" "🎯" "Service Selection"
    
    echo ""
    print_header "📋 Available Services"
    echo ""
    print_info "Select services to deploy. Dependencies will be auto-selected."
    echo ""
    
    # Infrastructure Services
    echo "🏗️  Infrastructure:"
    echo "  [1] PostgreSQL - Relational database"
    echo "  [2] Redis - Cache and message queue"
    echo "  [3] Tailscale - VPN mesh network"
    echo ""
    
    # AI Applications
    echo "🤖 AI Applications:"
    echo "  [4] Open WebUI - Modern ChatGPT-like interface"
    echo "  [5] AnythingLLM - Document-based AI chat"
    echo "  [6] Dify - LLM application development platform"
    echo "  [7] n8n - Workflow automation platform"
    echo "  [8] Flowise - Visual LangChain builder"
    echo "  [9] Ollama - Local LLM runtime"
    echo "  [10] LiteLLM - Multi-provider proxy + routing"
    echo ""
    
    # Communication & Integration
    echo "📱 Communication & Integration:"
    echo "  [11] Signal API - Private messaging"
    echo "  [12] OpenClaw UI - Multi-channel orchestration"
    echo ""
    
    # Monitoring
    echo "📊 Monitoring:"
    echo "  [13] Prometheus + Grafana - Metrics and visualization"
    echo ""
    
    # Storage
    echo "📦 Storage:"
    echo "  [14] MinIO - S3-compatible storage"
    echo ""
    
    echo "Select services (space-separated, e.g., '1 3 6'):"
    echo "Or enter 'all' to select all recommended services"
    echo ""
    
    local selected_services=()
    
    # Get user selection
    read -p "Services: " service_selection
    
    if [[ "$service_selection" == "all" ]]; then
        # Select all recommended services
        selected_services=("postgres" "redis" "ollama" "openwebui" "n8n" "prometheus")
        print_info "Selected all recommended services"
    else
        # Parse individual selections
        for num in $service_selection; do
            case "$num" in
                1) selected_services+=("postgres") ;;
                2) selected_services+=("redis") ;;
                3) selected_services+=("tailscale") ;;
                4) selected_services+=("openwebui") ;;
                5) selected_services+=("anythingllm") ;;
                6) selected_services+=("dify") ;;
                7) selected_services+=("n8n") ;;
                8) selected_services+=("flowise") ;;
                9) selected_services+=("ollama") ;;
                10) selected_services+=("litellm") ;;
                11) selected_services+=("signal-api") ;;
                12) selected_services+=("openclaw") ;;
                13) selected_services+=("prometheus") ;;
                14) selected_services+=("minio") ;;
                *) 
                    print_error "Invalid selection: $num"
                    ;;
            esac
        done
    fi
    
    # Add dependencies automatically
    local final_services=("${selected_services[@]}")
    
    # Always include postgres and redis if any AI app is selected
    for service in "${selected_services[@]}"; do
        case "$service" in
            openwebui|anythingllm|dify|n8n|flowise|ollama|litellm|openclaw)
                if [[ ! " ${final_services[*]} " =~ " postgres " ]]; then
                    final_services+=("postgres")
                    print_info "Auto-selected PostgreSQL (dependency)"
                fi
                if [[ ! " ${final_services[*]} " =~ " redis " ]]; then
                    final_services+=("redis")
                    print_info "Auto-selected Redis (dependency)"
                fi
                ;;
        esac
    done
    
    # Save selected services to JSON
    mkdir -p "$METADATA_DIR"
    cat > "$SERVICES_FILE" <<EOF
{
    "services": [
EOF
    
    local first=true
    for service in "${final_services[@]}"; do
        if [[ "$first" == "false" ]]; then
            echo "," >> "$SERVICES_FILE"
        fi
        first=false
        
        cat >> "$SERVICES_FILE" <<EOF
        {
            "key": "$service",
            "name": "$(echo "$service" | sed 's/-/ /g; s/\b\w/\u&/g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')",
            "category": "$(get_service_category "$service")",
            "selected": true
        }
EOF
    done
    
    cat >> "$SERVICES_FILE" <<EOF
    ]
}
EOF
    
    print_success "Services selection saved to $SERVICES_FILE"
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
