#!/bin/bash

#==============================================================================
# Script 3: Post-Deployment Configuration
# Purpose: Initialize databases, configure services, test integrations
# Version: 8.0.0 - Database Initialization & Service Configuration
#==============================================================================

set -euo pipefail

# Color definitions (matching Scripts 1 & 2)
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# Paths (matching Scripts 1 & 2)
readonly DATA_ROOT="/mnt/data"
readonly METADATA_DIR="$DATA_ROOT/metadata"
readonly STATE_FILE="$METADATA_DIR/setup_state.json"
readonly LOG_FILE="$DATA_ROOT/logs/configuration.log"
readonly ENV_FILE="$DATA_ROOT/.env"
readonly SERVICES_FILE="$METADATA_DIR/selected_services.json"
readonly COMPOSE_FILE="$DATA_ROOT/ai-platform/deployment/stack/docker-compose.yml"
readonly CONFIG_DIR="$DATA_ROOT/config"
readonly CREDENTIALS_FILE="$METADATA_DIR/credentials.json"

# Print functions (matching Scripts 1 & 2)
print_info() {
    echo -e "${CYAN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

print_phase() {
    local phase="$1"
    local icon="$2"
    local title="$3"
    echo ""
    echo -e "${BLUE}━━━ PHASE $phase: $icon $title ━━━${NC}" | tee -a "$LOG_FILE"
}

# Load environment
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Error: .env not found at $ENV_FILE${NC}"
    exit 1
fi

source "$ENV_FILE"

# Load selected services
if [ ! -f "$SERVICES_FILE" ]; then
    echo -e "${RED}Error: Selected services file not found. Run Script 1 first.${NC}"
    exit 1
fi

SELECTED_SERVICES=($(jq -r '.services[].key' "$SERVICES_FILE"))
TOTAL_SERVICES=${#SELECTED_SERVICES[@]}

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------

print_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║         🎨 AI Platform - UI Services Deployment            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_phase() {
    echo ""
    echo -e "${BLUE}${BOLD}[PHASE $1] $2${NC}"
}

print_step() {
    echo -e "${CYAN}[$1/$2]${NC} $3 $4"
}

print_success() {
    echo -e "${GREEN}  ✓${NC} $1"
}

print_error() {
    echo -e "${RED}  ✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}  ⚠${NC} $1"
}

print_info() {
    echo -e "${CYAN}  ℹ${NC} $1"
}

print_box_start() {
    echo "┌────────────────────────────────────────────────────────────┐"
}

print_box_line() {
    printf "│ %-58s │\n" "$1"
}

print_box_end() {
    echo "└────────────────────────────────────────────────────────────┘"
}

wait_for_service() {
    local service_name=$1
    local check_url=$2
    local max_attempts=${3:-60}
    local attempt=0
    
    echo -ne "${CYAN}  ⏳${NC} Waiting for $service_name"
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -sf "$check_url" > /dev/null 2>&1; then
            echo -e "\r${GREEN}  ✓${NC} $service_name is ready                    "
            return 0
        fi
        echo -ne "."
        sleep 2
        ((attempt++))
    done
    
    echo -e "\r${RED}  ✗${NC} $service_name failed to start (timeout)      "
    return 1
}

update_metadata() {
    local service=$1
    local status=$2
    local url=${3:-}
    
    if [[ -f "$METADATA_FILE" ]]; then
        local temp_file=$(mktemp)
        jq --arg service "$service" --arg status "$status" --arg url "$url" \
           '.ui_services += [{"name": $service, "status": $status, "url": $url, "deployed_at": now | strftime("%Y-%m-%d %H:%M:%S UTC")}] | 
            .last_updated = (now | strftime("%Y-%m-%d %H:%M:%S UTC"))' \
           "$METADATA_FILE" > "$temp_file"
        mv "$temp_file" "$METADATA_FILE"
    fi
}

#------------------------------------------------------------------------------
# Phase 1: Pre-Deployment Validation
#------------------------------------------------------------------------------

validate_prerequisites() {
    print_phase "1" "🔍 Pre-Deployment Validation"
    
    local validation_ok=true
    
    # Check core services are running
    print_info "Checking core services..."
    
    if ! docker ps | grep -q traefik; then
        print_error "Traefik is not running"
        validation_ok=false
    else
        print_success "Traefik is running"
    fi
    
    if ! docker ps | grep -q ollama; then
        print_error "Ollama is not running"
        validation_ok=false
    else
        print_success "Ollama is running"
    fi
    
    if ! docker ps | grep -q postgres; then
        print_error "PostgreSQL is not running"
        validation_ok=false
    else
        print_success "PostgreSQL is running"
    fi
    
    if ! docker ps | grep -q redis; then
        print_error "Redis is not running"
        validation_ok=false
    else
        print_success "Redis is running"
    fi
    
    # Check Ollama has models
    local model_count=$(curl -s http://localhost:11434/api/tags 2>/dev/null | jq -r '.models | length' 2>/dev/null || echo "0")
    if [[ "$model_count" -eq 0 ]]; then
        print_warning "No Ollama models found - UI may not function properly"
    else
        print_success "Ollama has $model_count model(s) available"
    fi
    
    if [[ "$validation_ok" == "false" ]]; then
        echo ""
        print_error "Validation failed. Please run script 2 first."
        exit 1
    fi
}

#------------------------------------------------------------------------------
# Phase 2: Generate UI Docker Compose
#------------------------------------------------------------------------------

generate_ui_compose() {
    print_phase "2" "📝 Generating UI Services Configuration"
    
    mkdir -p "$COMPOSE_DIR"
    
    print_info "Creating UI services compose file..."
    
    cat > "$COMPOSE_DIR/ui-services.yml" <<'EOF'
version: '3.8'

networks:
  ai_platform:
    external: true

services:
EOF

    # Add Open WebUI if enabled
    if [[ "${OPEN_WEBUI_ENABLED:-false}" == "true" ]]; then
        cat >> "$COMPOSE_DIR/ui-services.yml" <<'EOF'
  #----------------------------------------------------------------------------
  # Open WebUI - Primary Chat Interface
  #----------------------------------------------------------------------------
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: unless-stopped
    networks:
      - ai_platform
    ports:
      - "3000:8080"
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY:-secret-key-change-me}
      - WEBUI_AUTH=true
      - ENABLE_SIGNUP=${OPEN_WEBUI_ENABLE_SIGNUP:-true}
      - DEFAULT_USER_ROLE=${OPEN_WEBUI_DEFAULT_ROLE:-user}
      - ENABLE_ADMIN_EXPORT=true
      - ENABLE_COMMUNITY_SHARING=${OPEN_WEBUI_ENABLE_SHARING:-false}
      - WEBUI_NAME=${OPEN_WEBUI_NAME:-AI Platform}
    volumes:
      - ${DATA_DIR}/open-webui:/app/backend/data
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.open-webui.rule=Host(`chat.${DOMAIN:-localhost}`)"
      - "traefik.http.routers.open-webui.entrypoints=websecure"
      - "traefik.http.routers.open-webui.tls=true"
      - "traefik.http.services.open-webui.loadbalancer.server.port=8080"
    depends_on:
      - ollama

EOF
        print_success "Open WebUI configuration added"
    fi

    # Add AnythingLLM if enabled
    if [[ "${ANYTHINGLLM_ENABLED:-false}" == "true" ]]; then
        cat >> "$COMPOSE_DIR/ui-services.yml" <<'EOF'
  #----------------------------------------------------------------------------
  # AnythingLLM - Document Intelligence Platform
  #----------------------------------------------------------------------------
  anythingllm:
    image: mintplexlabs/anythingllm:latest
    container_name: anythingllm
    restart: unless-stopped
    networks:
      - ai_platform
    ports:
      - "3001:3001"
    environment:
      - STORAGE_DIR=/app/server/storage
      - OLLAMA_BASE_PATH=http://ollama:11434
      - VECTOR_DB=${ANYTHINGLLM_VECTOR_DB:-lancedb}
      - LLM_PROVIDER=ollama
      - EMBEDDING_ENGINE=ollama
      - AUTH_TOKEN=${ANYTHINGLLM_AUTH_TOKEN:-auth-token-change-me}
      - JWT_SECRET=${ANYTHINGLLM_JWT_SECRET:-jwt-secret-change-me}
      - DISABLE_TELEMETRY=true
    volumes:
      - ${DATA_DIR}/anythingllm:/app/server/storage
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.anythingllm.rule=Host(`docs.${DOMAIN:-localhost}`)"
      - "traefik.http.routers.anythingllm.entrypoints=websecure"
      - "traefik.http.routers.anythingllm.tls=true"
      - "traefik.http.services.anythingllm.loadbalancer.server.port=3001"
    depends_on:
      - ollama

EOF
        print_success "AnythingLLM configuration added"
    fi

    # Add Dify if enabled
    if [[ "${DIFY_ENABLED:-false}" == "true" ]]; then
        cat >> "$COMPOSE_DIR/ui-services.yml" <<'EOF'
  #============================================================================
# PHASE 1: Database Initialization
#============================================================================

initialize_databases() {
    print_phase "1" "🗄️" "Database Initialization"
    
    # Wait for postgres to be fully ready
    print_info "Waiting for PostgreSQL..."
    local retries=0
    while [ $retries -lt 30 ]; do
        if docker exec postgres pg_isready -U "${POSTGRES_USER:-aiplatform}" &>/dev/null; then
            print_success "PostgreSQL ready"
            break
        fi
        sleep 2
        retries=$((retries + 1))
    done
    
    if [ $retries -eq 30 ]; then
        print_error "PostgreSQL failed to become ready"
        return 1
    fi
    
    # Create databases for each service
    print_info "Creating databases for selected services..."
    
    # Check if postgres is in selected services
    if [[ " ${SELECTED_SERVICES[@]} " =~ " postgres " ]]; then
        # LiteLLM database
        if [[ " ${SELECTED_SERVICES[@]} " =~ " litellm " ]]; then
            print_info "Creating LiteLLM database..."
            docker exec postgres psql -U "${POSTGRES_USER:-aiplatform}" -c "CREATE DATABASE litellm;" 2>/dev/null || print_info "  litellm database already exists"
        fi
        
        # Dify database
        if [[ " ${SELECTED_SERVICES[@]} " =~ " dify-api " ]]; then
            print_info "Creating Dify database..."
            docker exec postgres psql -U "${POSTGRES_USER:-aiplatform}" -c "CREATE DATABASE dify;" 2>/dev/null || print_info "  dify database already exists"
        fi
        
        # n8n database
        if [[ " ${SELECTED_SERVICES[@]} " =~ " n8n " ]]; then
            print_info "Creating n8n database..."
            docker exec postgres psql -U "${POSTGRES_USER:-aiplatform}" -c "CREATE DATABASE n8n;" 2>/dev/null || print_info "  n8n database already exists"
        fi
        
        # Flowise database
        if [[ " ${SELECTED_SERVICES[@]} " =~ " flowise " ]]; then
            print_info "Creating Flowise database..."
            docker exec postgres psql -U "${POSTGRES_USER:-aiplatform}" -c "CREATE DATABASE flowise;" 2>/dev/null || print_info "  flowise database already exists"
        fi
    fi
    
    print_success "Database initialization completed"
}

#============================================================================
# PHASE 2: LiteLLM Configuration
#============================================================================

configure_litellm() {
    if [[ ! " ${SELECTED_SERVICES[@]} " =~ " litellm " ]]; then
        return 0
    fi
    
    print_phase "2" "🔗" "LiteLLM Configuration"
    
    # Wait for LiteLLM container to be ready
    print_info "Waiting for LiteLLM container..."
    local retries=0
    while [ $retries -lt 60 ]; do
        if docker ps --format '{{.Names}}' | grep -q "^litellm$"; then
            print_success "LiteLLM container is running"
            break
        fi
        sleep 2
        retries=$((retries + 1))
    done
    
    if [ $retries -eq 60 ]; then
        print_error "LiteLLM container failed to start"
        return 1
    fi
    
    # Initialize LiteLLM database
    print_info "Initializing LiteLLM database schema..."
    docker exec litellm python -c "from litellm.proxy.proxy_server import initialize; initialize()" 2>/dev/null || print_warning "LiteLLM schema initialization may have failed"
    
    # Test LiteLLM health
    print_info "Testing LiteLLM API..."
    if curl -s -f http://localhost:8010/health &>/dev/null; then
        print_success "LiteLLM API responding"
    else
        print_error "LiteLLM API not responding"
        docker logs litellm --tail 20
        return 1
    fi
    
    # Test Ollama connection
    if [[ " ${SELECTED_SERVICES[@]} " =~ " ollama " ]]; then
        print_info "Testing LiteLLM → Ollama connection..."
        if docker exec litellm curl -s http://ollama:11434/ &>/dev/null; then
            print_success "Ollama accessible from LiteLLM"
        else
            print_warning "Ollama not accessible from LiteLLM"
        fi
    fi
    
    print_success "LiteLLM configuration completed"
}

#------------------------------------------------------------------------------
# Phase 4: Generate Nginx Configuration for Dify
#------------------------------------------------------------------------------

generate_dify_nginx() {
    if [[ "${DIFY_ENABLED:-false}" != "true" ]]; then
        return 0
    fi
    
    print_phase "4" "⚙️ Configuring Dify Nginx"
    
    mkdir -p "$DATA_DIR/dify/nginx"
    
    cat > "$DATA_DIR/dify/nginx/nginx.conf" <<'EOF'
user  nginx;
worker_processes  auto;

error_log  /var/log/nginx/error.log notice;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    keepalive_timeout  65;

    upstream api {
        server dify-api:5001;
    }

    upstream web {
        server dify-web:3000;
    }

    server {
        listen 80;
        server_name _;

        location /console/api {
            proxy_pass http://api;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /api {
            proxy_pass http://api;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /v1 {
            proxy_pass http://api;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location / {
            proxy_pass http://web;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
EOF
    
    print_success "Dify Nginx configuration created"
}

#------------------------------------------------------------------------------
# Phase 5: Deploy UI Services
#------------------------------------------------------------------------------

deploy_ui_services() {
    print_phase "5" "🚀 Deploying UI Services"
    
    local step=1
    local total_steps=0
    
    # Count enabled services
    [[ "${OPEN_WEBUI_ENABLED:-false}" == "true" ]] && ((total_steps++))
    [[ "${ANYTHINGLLM_ENABLED:-false}" == "true" ]] && ((total_steps++))
    [[ "${DIFY_ENABLED:-false}" == "true" ]] && ((total_steps++))
    [[ "${LIBRECHAT_ENABLED:-false}" == "true" ]] && ((total_steps++))
    [[ "${FLOWISE_ENABLED:-false}" == "true" ]] && ((total_steps++))
    [[ "${N8N_ENABLED:-false}" == "true" ]] && ((total_steps++))
    
    if [[ $total_steps -eq 0 ]]; then
        print_warning "No UI services enabled in configuration"
        return 0
    fi
    
    # Deploy Open WebUI
    if [[ "${OPEN_WEBUI_ENABLED:-false}" == "true" ]]; then
        print_step "$step" "$total_steps" "💬" "Starting Open WebUI..."
        docker-compose -f "$COMPOSE_DIR/ui-services.yml" up -d open-webui
        sleep 10
        if wait_for_service "Open WebUI" "http://localhost:3000" 60; then
            update_metadata "open-webui" "running" "http://localhost:3000"
        fi
        ((step++))
    fi
    
    # Deploy AnythingLLM
    if [[ "${ANYTHINGLLM_ENABLED:-false}" == "true" ]]; then
        print_step "$step" "$total_steps" "📚" "Starting AnythingLLM..."
        docker-compose -f "$COMPOSE_DIR/ui-services.yml" up -d anythingllm
        sleep 15
        if wait_for_service "AnythingLLM" "http://localhost:3001" 60; then
            update_metadata "anythingllm" "running" "http://localhost:3001"
        fi
        ((step++))
    fi
    
    # Deploy Dify
    if [[ "${DIFY_ENABLED:-false}" == "true" ]]; then
        print_step "$step" "$total_steps" "🎯" "Starting Dify stack..."
        docker-compose -f "$COMPOSE_DIR/ui-services.yml" up -d dify-api dify-worker
        sleep 10
        docker-compose -f "$COMPOSE_DIR/ui-services.yml" up -d dify-web dify-nginx
        sleep 15
        if wait_for_service "Dify" "http://localhost:8000" 90; then
            update_metadata "dify" "running" "http://localhost:8000"
        fi
        ((step++))
    fi
    
    # Deploy LibreChat
    if [[ "${LIBRECHAT_ENABLED:-false}" == "true" ]]; then
        print_step "$step" "$total_steps" "💬" "Starting LibreChat..."
        docker-compose -f "$COMPOSE_DIR/ui-services.yml" up -d librechat-mongodb librechat-meilisearch
        sleep 10
        docker-compose -f "$COMPOSE_DIR/ui-services.yml" up -d librechat
        sleep 20
        if wait_for_service "LibreChat" "http://localhost:3003" 90; then
            update_metadata "librechat" "running" "http://localhost:3003"
        fi
        ((step++))
    fi
    
    # Deploy Flowise
    if [[ "${FLOWISE_ENABLED:-false}" == "true" ]]; then
        print_step "$step" "$total_steps" "🔀" "Starting Flowise..."
        docker-compose -f "$COMPOSE_DIR/ui-services.yml" up -d flowise
        sleep 15
        if wait_for_service "Flowise" "http://localhost:3004" 60; then
            update_metadata "flowise" "running" "http://localhost:3004"
        fi
        ((step++))
    fi
    
    # Deploy n8n
    if [[ "${N8N_ENABLED:-false}" == "true" ]]; then
        print_step "$step" "$total_steps" "⚡" "Starting n8n..."
        docker-compose -f "$COMPOSE_DIR/ui-services.yml" up -d n8n
        sleep 15
        if wait_for_service "n8n" "http://localhost:5678" 60; then
            update_metadata "n8n" "running" "http://localhost:5678"
        fi
        ((step++))
    fi
}

#------------------------------------------------------------------------------
# Phase 6: Service Health Check
#------------------------------------------------------------------------------

perform_health_check() {
    print_phase "6" "🏥 UI Services Health Check"
    
    print_box_start
    
    local all_healthy=true
    
    # Check each enabled service
    if [[ "${OPEN_WEBUI_ENABLED:-false}" == "true" ]]; then
        if curl -sf http://localhost:3000 > /dev/null 2>&1; then
            print_box_line "Open WebUI: ✓ Healthy (http://localhost:3000)"
        else
            print_box_line "Open WebUI: ✗ Unhealthy"
            all_healthy=false
        fi
    fi
    
    if [[ "${ANYTHINGLLM_ENABLED:-false}" == "true" ]]; then
        if curl -sf http://localhost:3001/api/ping > /dev/null 2>&1; then
            print_box_line "AnythingLLM: ✓ Healthy (http://localhost:3001)"
        else
            print_box_line "AnythingLLM: ✗ Unhealthy"
            all_healthy=false
        fi
    fi
    
    if [[ "${DIFY_ENABLED:-false}" == "true" ]]; then
        if curl -sf http://localhost:8000 > /dev/null 2>&1; then
            print_box_line "Dify: ✓ Healthy (http://localhost:8000)"
        else
            print_box_line "Dify: ✗ Unhealthy"
            all_healthy=false
        fi
    fi
    
    if [[ "${LIBRECHAT_ENABLED:-false}" == "true" ]]; then
        if curl -sf http://localhost:3003 > /dev/null 2>&1; then
            print_box_line "LibreChat: ✓ Healthy (http://localhost:3003)"
        else
            print_box_line "LibreChat: ✗ Unhealthy"
            all_healthy=false
        fi
    fi
    
    if [[ "${FLOWISE_ENABLED:-false}" == "true" ]]; then
        if curl -sf http://localhost:3004 > /dev/null 2>&1; then
            print_box_line "Flowise: ✓ Healthy (http://localhost:3004)"
        else
            print_box_line "Flowise: ✗ Unhealthy"
            all_healthy=false
        fi
    fi
    
    if [[ "${N8N_ENABLED:-false}" == "true" ]]; then
        if curl -sf http://localhost:5678 > /dev/null 2>&1; then
            print_box_line "n8n: ✓ Healthy (http://localhost:5678)"
        else
            print_box_line "n8n: ✗ Unhealthy"
            all_healthy=false
        fi
    fi
    
    print_box_end
    
    if [[ "$all_healthy" == "true" ]]; then
        print_success "All UI services are healthy"
    else
        print_warning "Some UI services are unhealthy - check logs"
    fi
}

#------------------------------------------------------------------------------
# Phase 7: Generate Access Instructions
#------------------------------------------------------------------------------

generate_access_info() {
    print_phase "7" "📋 Generating Access Information"
    
    local access_file="$DATA_DIR/UI_ACCESS.md"
    
    cat > "$access_file" <<EOF
# AI Platform - UI Access Information

Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## Available Interfaces

EOF

    if [[ "${OPEN_WEBUI_ENABLED:-false}" == "true" ]]; then
        cat >> "$access_file" <<EOF
### Open WebUI (Primary Chat Interface)
- **URL**: http://localhost:3000
- **Domain**: https://chat.${DOMAIN:-localhost}
- **Description**: ChatGPT-like interface for Ollama models
- **First Login**: Create admin account on first visit

EOF
    fi

    if [[ "${ANYTHINGLLM_ENABLED:-false}" == "true" ]]; then
        cat >> "$access_file" <<EOF
### AnythingLLM (Document Intelligence)
- **URL**: http://localhost:3001
- **Domain**: https://docs.${DOMAIN:-localhost}
- **Auth Token**: ${ANYTHINGLLM_AUTH_TOKEN:-Check .env file}
- **Description**: RAG-powered document chat and analysis

EOF
    fi

    if [[ "${DIFY_ENABLED:-false}" == "true" ]]; then
        cat >> "$access_file" <<EOF
### Dify (LLM App Development)
- **URL**: http://localhost:8000
- **Domain**: https://dify.${DOMAIN:-localhost}
- **API**: http://localhost:8000/v1
- **Description**: Visual workflow builder for LLM applications
- **First Login**: Create account on first visit

EOF
    fi

    if [[ "${LIBRECHAT_ENABLED:-false}" == "true" ]]; then
        cat >> "$access_file" <<EOF
### LibreChat (Multi-Model Interface)
- **URL**: http://localhost:3003
- **Domain**: https://librechat.${DOMAIN:-localhost}
- **Description**: ChatGPT-style UI supporting multiple providers
- **Registration**: ${LIBRECHAT_ALLOW_REGISTRATION:-Enabled}

EOF
    fi

    if [[ "${FLOWISE_ENABLED:-false}" == "true" ]]; then
        cat >> "$access_file" <<EOF
### Flowise (Visual Flow Builder)
- **URL**: http://localhost:3004
- **Domain**: https://flowise.${DOMAIN:-localhost}
- **Username**: ${FLOWISE_USERNAME:-admin}
- **Password**: ${FLOWISE_PASSWORD:-Check .env file}
- **Description**: Drag-and-drop LLM app builder

EOF
    fi

    if [[ "${N8N_ENABLED:-false}" == "true" ]]; then
        cat >> "$access_file" <<EOF
### n8n (Workflow Automation)
- **URL**: http://localhost:5678
- **Domain**: https://n8n.${DOMAIN:-localhost}
- **Description**: Workflow automation with 400+ integrations
- **First Login**: Create account on first visit

EOF
    fi

    cat >> "$access_file" <<EOF
## Core Services

### Ollama (LLM Runtime)
- **API**: http://localhost:11434
- **Models**: http://localhost:11434/api/tags

### Traefik (Reverse Proxy)
- **Dashboard**: http://localhost:8080

$(if [[ "${VECTOR_DB:-none}" != "none" ]]; then
    case "${VECTOR_DB}" in
        "qdrant") echo "### Qdrant (Vector Database)
- **API**: http://localhost:6333
- **Dashboard**: http://localhost:6333/dashboard" ;;
        "weaviate") echo "### Weaviate (Vector Database)
- **API**: http://localhost:8080/v1" ;;
        "milvus") echo "### Milvus (Vector Database)
- **gRPC**: localhost:19530
- **HTTP**: http://localhost:9091" ;;
    esac
fi)

$(if [[ "${LITELLM_ENABLED:-false}" == "true" ]]; then
    echo "### LiteLLM (API Gateway)
- **API**: http://localhost:4000
- **Docs**: http://localhost:4000/docs
- **Master Key**: ${LITELLM_MASTER_KEY:-Check .env file}"
fi)

## Quick Start Commands

\`\`\`bash
# View all logs
docker-compose -f $COMPOSE_DIR/ui-services.yml logs -f

# Restart a service
docker-compose -f $COMPOSE_DIR/ui-services.yml restart <service>

# Stop all UI services
docker-compose -f $COMPOSE_DIR/ui-services.yml down

# Update a service
docker-compose -f $COMPOSE_DIR/ui-services.yml pull <service>
docker-compose -f $COMPOSE_DIR/ui-services.yml up -d <service>
\`\`\`

## Security Notes

1. Change all default passwords in $ENV_FILE
2. Enable HTTPS via Traefik for production
3. Configure authentication for all services
4. Restrict network access as needed
5. Enable backup automation (Script 4)

## Support

For issues or questions:
- Check logs: \`docker logs <container-name>\`
- Review documentation in project README
- Check service-specific documentation

EOF

    print_success "Access information saved to: $access_file"
    cat "$access_file"
}

#------------------------------------------------------------------------------
# Final Success Message
#------------------------------------------------------------------------------

print_final_success() {
    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║           ✅ UI SERVICES DEPLOYED SUCCESSFULLY             ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo -e "${BOLD}🌐 Available Interfaces:${NC}"
    
    [[ "${OPEN_WEBUI_ENABLED:-false}" == "true" ]] && echo "  • Open WebUI: ${CYAN}http://localhost:3000${NC}"
    [[ "${ANYTHINGLLM_ENABLED:-false}" == "true" ]] && echo "  • AnythingLLM: ${CYAN}http://localhost:3001${NC}"
    [[ "${DIFY_ENABLED:-false}" == "true" ]] && echo "  • Dify: ${CYAN}http://localhost:8000${NC}"
    [[ "${LIBRECHAT_ENABLED:-false}" == "true" ]] && echo "  • LibreChat: ${CYAN}http://localhost:3003${NC}"
    [[ "${FLOWISE_ENABLED:-false}" == "true" ]] && echo "  • Flowise: ${CYAN}http://localhost:3004${NC}"
    [[ "${N8N_ENABLED:-false}" == "true" ]] && echo "  • n8n: ${CYAN}http://localhost:5678${NC}"
    
    echo ""
    echo -e "${BOLD}📋 Access Info:${NC} ${CYAN}$DATA_DIR/UI_ACCESS.md${NC}"
    echo ""
    echo -e "${BOLD}Next Steps:${NC}"
    echo "  1. Access any UI above and create your account"
    echo "  2. Configure integrations (optional)"
    echo "  3. Setup monitoring: ${CYAN}./scripts/4-monitoring-backup.sh${NC}"
    echo ""
    echo -e "${BOLD}Useful Commands:${NC}"
    echo "  • View logs: ${CYAN}docker-compose -f $COMPOSE_DIR/ui-services.yml logs -f${NC}"
    echo "  • Restart service: ${CYAN}docker-compose -f $COMPOSE_DIR/ui-services.yml restart <name>${NC}"
    echo ""
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------

main() {
    print_header
    
    validate_prerequisites
    generate_ui_compose
    initialize_databases
    generate_dify_nginx
    deploy_ui_services
    perform_health_check
    generate_access_info
    
    print_final_success
}

main "$@"
