#!/bin/bash

#==============================================================================
# Script 3: Deploy UI Services
# Purpose: Deploy Open WebUI, AnythingLLM, Dify, and other frontends
# Per README: User Interface Layer Deployment
#==============================================================================

set -euo pipefail

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# Paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly DATA_DIR="/mnt/data"
readonly CONFIG_DIR="$DATA_DIR/config"
readonly COMPOSE_DIR="$DATA_DIR/compose"
readonly METADATA_FILE="$DATA_DIR/.platform_metadata.json"
readonly ENV_FILE="$DATA_DIR/.env"

# Source environment
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
else
    echo -e "${RED}Error: Environment file not found. Run scripts 1-2 first.${NC}"
    exit 1
fi

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
  #----------------------------------------------------------------------------
  # Dify - LLM Application Development Platform
  #----------------------------------------------------------------------------
  dify-api:
    image: langgenius/dify-api:latest
    container_name: dify-api
    restart: unless-stopped
    networks:
      - ai_platform
    environment:
      - MODE=api
      - LOG_LEVEL=INFO
      - SECRET_KEY=${DIFY_SECRET_KEY}
      - DB_USERNAME=${POSTGRES_USER:-aiplatform}
      - DB_PASSWORD=${POSTGRES_PASSWORD}
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_DATABASE=dify
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=${REDIS_PASSWORD}
      - REDIS_USE_SSL=false
      - REDIS_DB=1
      - CELERY_BROKER_URL=redis://:${REDIS_PASSWORD}@redis:6379/2
      - WEB_API_CORS_ALLOW_ORIGINS=*
      - CONSOLE_CORS_ALLOW_ORIGINS=*
      - STORAGE_TYPE=local
      - STORAGE_LOCAL_PATH=/app/storage
      - VECTOR_STORE=${VECTOR_DB:-qdrant}
      - QDRANT_URL=http://qdrant:6333
      - QDRANT_API_KEY=${QDRANT_API_KEY:-}
    volumes:
      - ${DATA_DIR}/dify/api/storage:/app/storage
    depends_on:
      - postgres
      - redis

  dify-worker:
    image: langgenius/dify-api:latest
    container_name: dify-worker
    restart: unless-stopped
    networks:
      - ai_platform
    environment:
      - MODE=worker
      - LOG_LEVEL=INFO
      - SECRET_KEY=${DIFY_SECRET_KEY}
      - DB_USERNAME=${POSTGRES_USER:-aiplatform}
      - DB_PASSWORD=${POSTGRES_PASSWORD}
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_DATABASE=dify
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=${REDIS_PASSWORD}
      - REDIS_DB=1
      - CELERY_BROKER_URL=redis://:${REDIS_PASSWORD}@redis:6379/2
      - STORAGE_TYPE=local
      - STORAGE_LOCAL_PATH=/app/storage
      - VECTOR_STORE=${VECTOR_DB:-qdrant}
      - QDRANT_URL=http://qdrant:6333
    volumes:
      - ${DATA_DIR}/dify/worker/storage:/app/storage
    depends_on:
      - postgres
      - redis

  dify-web:
    image: langgenius/dify-web:latest
    container_name: dify-web
    restart: unless-stopped
    networks:
      - ai_platform
    ports:
      - "3002:3000"
    environment:
      - CONSOLE_API_URL=http://dify-api:5001
      - APP_API_URL=http://dify-api:5001
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.dify.rule=Host(`dify.${DOMAIN:-localhost}`)"
      - "traefik.http.routers.dify.entrypoints=websecure"
      - "traefik.http.routers.dify.tls=true"
      - "traefik.http.services.dify.loadbalancer.server.port=3000"
    depends_on:
      - dify-api

  dify-nginx:
    image: nginx:alpine
    container_name: dify-nginx
    restart: unless-stopped
    networks:
      - ai_platform
    ports:
      - "8000:80"
    volumes:
      - ${DATA_DIR}/dify/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - dify-api
      - dify-web

EOF
        print_success "Dify configuration added"
    fi

    # Add LibreChat if enabled
    if [[ "${LIBRECHAT_ENABLED:-false}" == "true" ]]; then
        cat >> "$COMPOSE_DIR/ui-services.yml" <<'EOF'
  #----------------------------------------------------------------------------
  # LibreChat - Multi-Model Chat Interface
  #----------------------------------------------------------------------------
  librechat-mongodb:
    image: mongo:latest
    container_name: librechat-mongodb
    restart: unless-stopped
    networks:
      - ai_platform
    environment:
      - MONGO_INITDB_ROOT_USERNAME=${MONGODB_USER:-admin}
      - MONGO_INITDB_ROOT_PASSWORD=${MONGODB_PASSWORD:-mongodb_secure_password}
    volumes:
      - ${DATA_DIR}/librechat/mongodb:/data/db
    command: mongod --quiet --logpath /dev/null

  librechat-meilisearch:
    image: getmeili/meilisearch:latest
    container_name: librechat-meilisearch
    restart: unless-stopped
    networks:
      - ai_platform
    environment:
      - MEILI_HOST=http://librechat-meilisearch:7700
      - MEILI_NO_ANALYTICS=true
    volumes:
      - ${DATA_DIR}/librechat/meilisearch:/meili_data

  librechat:
    image: ghcr.io/danny-avila/librechat:latest
    container_name: librechat
    restart: unless-stopped
    networks:
      - ai_platform
    ports:
      - "3003:3080"
    environment:
      - HOST=0.0.0.0
      - MONGO_URI=mongodb://${MONGODB_USER:-admin}:${MONGODB_PASSWORD:-mongodb_secure_password}@librechat-mongodb:27017/LibreChat?authSource=admin
      - MEILI_HOST=http://librechat-meilisearch:7700
      - CREDS_KEY=${LIBRECHAT_CREDS_KEY:-creds-key-change-me-32-chars}
      - CREDS_IV=${LIBRECHAT_CREDS_IV:-creds-iv-change-me-16-chars}
      - JWT_SECRET=${LIBRECHAT_JWT_SECRET:-jwt-secret-change-me}
      - ALLOW_EMAIL_LOGIN=true
      - ALLOW_REGISTRATION=${LIBRECHAT_ALLOW_REGISTRATION:-true}
      - OLLAMA_BASE_URL=http://ollama:11434
    volumes:
      - ${DATA_DIR}/librechat/config:/app/librechat.yaml:ro
      - ${DATA_DIR}/librechat/images:/app/client/public/images
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.librechat.rule=Host(`librechat.${DOMAIN:-localhost}`)"
      - "traefik.http.routers.librechat.entrypoints=websecure"
      - "traefik.http.routers.librechat.tls=true"
      - "traefik.http.services.librechat.loadbalancer.server.port=3080"
    depends_on:
      - librechat-mongodb
      - librechat-meilisearch
      - ollama

EOF
        print_success "LibreChat configuration added"
    fi

    # Add Flowise if enabled
    if [[ "${FLOWISE_ENABLED:-false}" == "true" ]]; then
        cat >> "$COMPOSE_DIR/ui-services.yml" <<'EOF'
  #----------------------------------------------------------------------------
  # Flowise - Visual Flow Builder for LLM Apps
  #----------------------------------------------------------------------------
  flowise:
    image: flowiseai/flowise:latest
    container_name: flowise
    restart: unless-stopped
    networks:
      - ai_platform
    ports:
      - "3004:3000"
    environment:
      - PORT=3000
      - FLOWISE_USERNAME=${FLOWISE_USERNAME:-admin}
      - FLOWISE_PASSWORD=${FLOWISE_PASSWORD:-flowise_secure_password}
      - APIKEY_PATH=/root/.flowise
      - DATABASE_TYPE=postgres
      - DATABASE_HOST=postgres
      - DATABASE_PORT=5432
      - DATABASE_NAME=flowise
      - DATABASE_USER=${POSTGRES_USER:-aiplatform}
      - DATABASE_PASSWORD=${POSTGRES_PASSWORD}
      - EXECUTION_MODE=main
    volumes:
      - ${DATA_DIR}/flowise:/root/.flowise
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.flowise.rule=Host(`flowise.${DOMAIN:-localhost}`)"
      - "traefik.http.routers.flowise.entrypoints=websecure"
      - "traefik.http.routers.flowise.tls=true"
      - "traefik.http.services.flowise.loadbalancer.server.port=3000"
    depends_on:
      - postgres

EOF
        print_success "Flowise configuration added"
    fi

    # Add n8n if enabled
    if [[ "${N8N_ENABLED:-false}" == "true" ]]; then
        cat >> "$COMPOSE_DIR/ui-services.yml" <<'EOF'
  #----------------------------------------------------------------------------
  # n8n - Workflow Automation
  #----------------------------------------------------------------------------
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    networks:
      - ai_platform
    ports:
      - "5678:5678"
    environment:
      - N8N_HOST=${DOMAIN:-localhost}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://n8n.${DOMAIN:-localhost}/
      - GENERIC_TIMEZONE=UTC
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=${POSTGRES_USER:-aiplatform}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY:-n8n-encryption-key-change-me}
    volumes:
      - ${DATA_DIR}/n8n:/home/node/.n8n
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(`n8n.${DOMAIN:-localhost}`)"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.tls=true"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"
    depends_on:
      - postgres

EOF
        print_success "n8n configuration added"
    fi
}

#------------------------------------------------------------------------------
# Phase 3: Initialize Databases for UI Services
#------------------------------------------------------------------------------

initialize_databases() {
    print_phase "3" "💾 Initializing UI Service Databases"
    
    # Create databases for each UI service
    if [[ "${DIFY_ENABLED:-false}" == "true" ]]; then
        print_info "Creating Dify database..."
        docker exec postgres psql -U "${POSTGRES_USER:-aiplatform}" -c "CREATE DATABASE dify;" 2>/dev/null || print_warning "Dify database may already exist"
        print_success "Dify database ready"
    fi
    
    if [[ "${FLOWISE_ENABLED:-false}" == "true" ]]; then
        print_info "Creating Flowise database..."
        docker exec postgres psql -U "${POSTGRES_USER:-aiplatform}" -c "CREATE DATABASE flowise;" 2>/dev/null || print_warning "Flowise database may already exist"
        print_success "Flowise database ready"
    fi
    
    if [[ "${N8N_ENABLED:-false}" == "true" ]]; then
        print_info "Creating n8n database..."
        docker exec postgres psql -U "${POSTGRES_USER:-aiplatform}" -c "CREATE DATABASE n8n;" 2>/dev/null || print_warning "n8n database may already exist"
        print_success "n8n database ready"
    fi
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
