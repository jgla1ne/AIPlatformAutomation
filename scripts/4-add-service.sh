#!/bin/bash
# 4-add-service.sh - Add new services to existing deployment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_ROOT="/mnt/data"
METADATA_DIR="$DATA_ROOT/metadata"
COMPOSE_DIR="$DATA_ROOT/compose"
ENV_DIR="$DATA_ROOT/env"
CONFIG_DIR="$DATA_ROOT/config"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

show_banner() {
    cat << 'EOF'
╔════════════════════════════════════════════════════════════╗
║   🚀 AIPlatformAutomation - Add Service v76.5             ║
╚════════════════════════════════════════════════════════════╝

    Add new services to your existing platform deployment
    
EOF
}

check_prerequisites() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    if [ ! -f "$METADATA_DIR/selected_services.json" ]; then
        log_error "Platform not deployed. Run ./2-deploy-services.sh first"
        exit 1
    fi
    
    # Detect real user
    if [ -n "${SUDO_USER:-}" ]; then
        REAL_USER="$SUDO_USER"
    else
        REAL_USER="$USER"
    fi
    
    PUID=$(id -u "$REAL_USER")
    PGID=$(id -g "$REAL_USER")
}

load_config() {
    DOMAIN=$(jq -r '.domain' "$METADATA_DIR/network_config.json")
    VECTORDB_TYPE=$(jq -r '.type' "$METADATA_DIR/vectordb_config.json" 2>/dev/null || echo "none")
    DEPLOYED_SERVICES=($(jq -r '.applications[]' "$METADATA_DIR/selected_services.json"))
}

# Service catalog with descriptions and dependencies
declare -A SERVICE_DESCRIPTIONS
SERVICE_DESCRIPTIONS=(
    ["open-webui"]="Modern web UI for LLMs (Ollama/LiteLLM) - No dependencies"
    ["anythingllm"]="Document-based chat with RAG - Requires: VectorDB"
    ["dify"]="LLM app development platform - Requires: VectorDB, PostgreSQL, Redis"
    ["n8n"]="Workflow automation - Requires: PostgreSQL"
    ["flowise"]="Drag-and-drop LLM workflows - Requires: PostgreSQL"
    ["comfyui"]="Advanced image generation - No dependencies"
    ["openclaw-ui"]="Communication orchestration UI - No dependencies"
    ["signal-api"]="Signal messaging integration - No dependencies"
    ["gdrive-sync"]="Google Drive sync service - No dependencies"
)

declare -A SERVICE_DEPS
SERVICE_DEPS=(
    ["open-webui"]=""
    ["anythingllm"]="vectordb"
    ["dify"]="vectordb postgres redis"
    ["n8n"]="postgres"
    ["flowise"]="postgres"
    ["comfyui"]=""
    ["openclaw-ui"]=""
    ["signal-api"]=""
    ["gdrive-sync"]=""
)

show_service_catalog() {
    clear
    cat << EOF
╔════════════════════════════════════════════════════════════╗
║               📦 AVAILABLE SERVICES                        ║
╚════════════════════════════════════════════════════════════╝

${CYAN}Currently Deployed:${NC}
EOF
    
    for service in "${DEPLOYED_SERVICES[@]}"; do
        echo "  ✅ $service"
    done
    
    cat << EOF

${CYAN}Available to Add:${NC}

EOF
    
    local index=1
    for service in "${!SERVICE_DESCRIPTIONS[@]}"; do
        # Check if not already deployed
        if [[ ! " ${DEPLOYED_SERVICES[@]} " =~ " ${service} " ]]; then
            printf "  ${YELLOW}%-2d)${NC} %-20s - %s\n" \
                "$index" \
                "$service" \
                "${SERVICE_DESCRIPTIONS[$service]}"
            SERVICE_OPTIONS[$index]=$service
            ((index++))
        fi
    done
    
    cat << EOF

  ${YELLOW}0)${NC}  Exit

EOF
}

check_dependencies() {
    local service=$1
    local deps="${SERVICE_DEPS[$service]}"
    local missing_deps=()
    
    if [ -z "$deps" ]; then
        return 0
    fi
    
    for dep in $deps; do
        case $dep in
            vectordb)
                if [ "$VECTORDB_TYPE" = "none" ]; then
                    missing_deps+=("Vector Database")
                fi
                ;;
            postgres)
                if ! docker ps | grep -q postgres; then
                    missing_deps+=("PostgreSQL")
                fi
                ;;
            redis)
                if ! docker ps | grep -q redis; then
                    missing_deps+=("Redis")
                fi
                ;;
        esac
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing dependencies for $service:"
        printf '  • %s\n' "${missing_deps[@]}"
        return 1
    fi
    
    return 0
}

check_port_conflicts() {
    local service=$1
    local port
    
    case $service in
        open-webui) port=8080 ;;
        anythingllm) port=3001 ;;
        dify) port=3002 ;;
        n8n) port=5678 ;;
        flowise) port=3003 ;;
        comfyui) port=8188 ;;
        openclaw-ui) port=3000 ;;
        signal-api) port=8090 ;;
        *) return 0 ;;
    esac
    
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        log_error "Port $port is already in use"
        return 1
    fi
    
    return 0
}

generate_service_compose() {
    local service=$1
    
    case $service in
        open-webui) generate_openwebui_compose ;;
        anythingllm) generate_anythingllm_compose ;;
        dify) generate_dify_compose ;;
        n8n) generate_n8n_compose ;;
        flowise) generate_flowise_compose ;;
        comfyui) generate_comfyui_compose ;;
        openclaw-ui) generate_openclaw_compose ;;
        signal-api) generate_signal_compose ;;
        gdrive-sync) generate_gdrive_compose ;;
    esac
}

generate_openwebui_compose() {
    cat > "$COMPOSE_DIR/open-webui.yml" << 'EOF'
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    env_file: /mnt/data/env/open-webui.env
    volumes:
      - /mnt/data/data/open-webui:/app/backend/data
    ports:
      - "8080:8080"
    restart: unless-stopped
    networks:
      - aiplatform
    depends_on:
      - ollama
      - litellm

networks:
  aiplatform:
    external: true
EOF
    
    cat > "$ENV_DIR/open-webui.env" << ENV
OLLAMA_BASE_URL=http://ollama:11434
OPENAI_API_BASE_URL=http://litellm:4000/v1
OPENAI_API_KEY=$(cat "$ENV_DIR/litellm.env" | grep LITELLM_MASTER_KEY | cut -d= -f2)
WEBUI_NAME=AI Platform - Open WebUI
ENABLE_RAG_WEB_SEARCH=true
ENV
}

generate_anythingllm_compose() {
    cat > "$COMPOSE_DIR/anythingllm.yml" << EOF
services:
  anythingllm:
    image: mintplexlabs/anythingllm:latest
    container_name: anythingllm
    env_file: /mnt/data/env/anythingllm.env
    volumes:
      - /mnt/data/data/anythingllm:/app/server/storage
    ports:
      - "3001:3001"
    restart: unless-stopped
    networks:
      - aiplatform

networks:
  aiplatform:
    external: true
EOF
    
    # Get vector DB connection details
    case $VECTORDB_TYPE in
        qdrant)
            VECTORDB_URL="http://qdrant:6333"
            VECTORDB_API_KEY=$(cat "$ENV_DIR/qdrant.env" | grep QDRANT_API_KEY | cut -d= -f2)
            ;;
        chromadb)
            VECTORDB_URL="http://chromadb:8000"
            VECTORDB_API_KEY=""
            ;;
        *)
            VECTORDB_URL=""
            VECTORDB_API_KEY=""
            ;;
    esac
    
    cat > "$ENV_DIR/anythingllm.env" << ENV
LLM_PROVIDER=openai
OPEN_AI_KEY=$(cat "$ENV_DIR/litellm.env" | grep LITELLM_MASTER_KEY | cut -d= -f2)
OPENAI_API_BASE=http://litellm:4000/v1
VECTOR_DB=$VECTORDB_TYPE
${VECTORDB_TYPE^^}_API_ENDPOINT=$VECTORDB_URL
${VECTORDB_TYPE^^}_API_KEY=$VECTORDB_API_KEY
EMBEDDING_ENGINE=ollama
EMBEDDING_BASE_PATH=http://ollama:11434
EMBEDDING_MODEL_PREF=nomic-embed-text
ENV
}

generate_dify_compose() {
    POSTGRES_PASSWORD=$(cat "$ENV_DIR/postgres.env" | grep POSTGRES_PASSWORD | cut -d= -f2)
    REDIS_PASSWORD=$(cat "$ENV_DIR/redis.env" | grep REDIS_PASSWORD | cut -d= -f2)
    SECRET_KEY=$(openssl rand -hex 32)
    
    cat > "$COMPOSE_DIR/dify-api.yml" << EOF
services:
  dify-api:
    image: langgenius/dify-api:latest
    container_name: dify-api
    env_file: /mnt/data/env/dify.env
    volumes:
      - /mnt/data/data/dify:/app/api/storage
    ports:
      - "5001:5001"
    restart: unless-stopped
    networks:
      - aiplatform
    depends_on:
      - postgres
      - redis

networks:
  aiplatform:
    external: true
EOF
    
    cat > "$COMPOSE_DIR/dify-worker.yml" << EOF
services:
  dify-worker:
    image: langgenius/dify-api:latest
    container_name: dify-worker
    env_file: /mnt/data/env/dify.env
    command: celery -A app.celery worker -P gevent -c 1 -Q dataset,generation,mail
    restart: unless-stopped
    networks:
      - aiplatform
    depends_on:
      - postgres
      - redis

networks:
  aiplatform:
    external: true
EOF
    
    cat > "$COMPOSE_DIR/dify-web.yml" << EOF
services:
  dify-web:
    image: langgenius/dify-web:latest
    container_name: dify-web
    environment:
      - CONSOLE_API_URL=http://dify-api:5001
      - APP_API_URL=http://dify-api:5001
    ports:
      - "3002:3000"
    restart: unless-stopped
    networks:
      - aiplatform
    depends_on:
      - dify-api

networks:
  aiplatform:
    external: true
EOF
    
    cat > "$ENV_DIR/dify.env" << ENV
MODE=api
SECRET_KEY=$SECRET_KEY
DB_USERNAME=aiplatform
DB_PASSWORD=$POSTGRES_PASSWORD
DB_HOST=postgres
DB_PORT=5432
DB_DATABASE=dify
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=$REDIS_PASSWORD
CELERY_BROKER_URL=redis://:$REDIS_PASSWORD@redis:6379/1
VECTOR_STORE=$VECTORDB_TYPE
ENV

    case $VECTORDB_TYPE in
        qdrant)
            QDRANT_API_KEY=$(cat "$ENV_DIR/qdrant.env" | grep QDRANT_API_KEY | cut -d= -f2)
            cat >> "$ENV_DIR/dify.env" << VECTORENV
QDRANT_URL=http://qdrant:6333
QDRANT_API_KEY=$QDRANT_API_KEY
VECTORENV
            ;;
    esac
}

generate_n8n_compose() {
    POSTGRES_PASSWORD=$(cat "$ENV_DIR/postgres.env" | grep POSTGRES_PASSWORD | cut -d= -f2)
    
    cat > "$COMPOSE_DIR/n8n.yml" << EOF
services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    env_file: /mnt/data/env/n8n.env
    volumes:
      - /mnt/data/data/n8n:/home/node/.n8n
    ports:
      - "5678:5678"
    restart: unless-stopped
    networks:
      - aiplatform
    depends_on:
      - postgres

networks:
  aiplatform:
    external: true
EOF
    
    cat > "$ENV_DIR/n8n.env" << ENV
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=aiplatform
DB_POSTGRESDB_PASSWORD=$POSTGRES_PASSWORD
N8N_HOST=$DOMAIN
N8N_PORT=5678
N8N_PROTOCOL=https
WEBHOOK_URL=https://$DOMAIN/
ENV
}

generate_flowise_compose() {
    POSTGRES_PASSWORD=$(cat "$ENV_DIR/postgres.env" | grep POSTGRES_PASSWORD | cut -d= -f2)
    
    cat > "$COMPOSE_DIR/flowise.yml" << EOF
services:
  flowise:
    image: flowiseai/flowise:latest
    container_name: flowise
    env_file: /mnt/data/env/flowise.env
    volumes:
      - /mnt/data/data/flowise:/root/.flowise
    ports:
      - "3003:3000"
    restart: unless-stopped
    networks:
      - aiplatform
    depends_on:
      - postgres

networks:
  aiplatform:
    external: true
EOF
    
    cat > "$ENV_DIR/flowise.env" << ENV
DATABASE_TYPE=postgres
DATABASE_HOST=postgres
DATABASE_PORT=5432
DATABASE_USER=aiplatform
DATABASE_PASSWORD=$POSTGRES_PASSWORD
DATABASE_NAME=flowise
FLOWISE_USERNAME=admin
FLOWISE_PASSWORD=$(openssl rand -base64 16)
ENV
}

generate_comfyui_compose() {
    GPU_AVAILABLE=$(lspci | grep -i nvidia &>/dev/null && echo "true" || echo "false")
    
    cat > "$COMPOSE_DIR/comfyui.yml" << EOF
services:
  comfyui:
    image: yanwk/comfyui-boot:latest
    container_name: comfyui
    env_file: /mnt/data/env/comfyui.env
    volumes:
      - /mnt/data/data/comfyui:/home/runner
    ports:
      - "8188:8188"
    restart: unless-stopped
    networks:
      - aiplatform
EOF
    
    if [ "$GPU_AVAILABLE" = "true" ]; then
        cat >> "$COMPOSE_DIR/comfyui.yml" << EOF
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
EOF
    fi
    
    cat >> "$COMPOSE_DIR/comfyui.yml" << EOF

networks:
  aiplatform:
    external: true
EOF
    
    cat > "$ENV_DIR/comfyui.env" << ENV
COMFYUI_FLAGS=--listen 0.0.0.0 --port 8188
ENV
}

generate_openclaw_compose() {
    cat > "$COMPOSE_DIR/openclaw-ui.yml" << EOF
services:
  openclaw-ui:
    image: openclaw/openclaw-ui:latest
    container_name: openclaw-ui
    env_file: /mnt/data/env/openclaw-ui.env
    volumes:
      - /mnt/data/data/openclaw:/app/data
    ports:
      - "3000:3000"
    restart: unless-stopped
    networks:
      - aiplatform

networks:
  aiplatform:
    external: true
EOF
    
    LITELLM_KEY=$(cat "$ENV_DIR/litellm.env" | grep LITELLM_MASTER_KEY | cut -d= -f2)
    
    cat > "$ENV_DIR/openclaw-ui.env" << ENV
LLM_API_URL=http://litellm:4000/v1
LLM_API_KEY=$LITELLM_KEY
SIGNAL_API_URL=http://signal-api:8090
ENV
}

generate_signal_compose() {
    cat > "$COMPOSE_DIR/signal-api.yml" << EOF
services:
  signal-api:
    image: bbernhard/signal-cli-rest-api:latest
    container_name: signal-api
    env_file: /mnt/data/env/signal-api.env
    volumes:
      - /mnt/data/data/signal-api:/home/.local/share/signal-cli
    ports:
      - "8090:8080"
    restart: unless-stopped
    networks:
      - aiplatform

networks:
  aiplatform:
    external: true
EOF
    
    cat > "$ENV_DIR/signal-api.env" << ENV
MODE=json-rpc
EOF
}

generate_gdrive_compose() {
    cat > "$COMPOSE_DIR/gdrive-sync.yml" << EOF
services:
  gdrive-sync:
    image: rclone/rclone:latest
    container_name: gdrive-sync
    env_file: /mnt/data/env/gdrive-sync.env
    volumes:
      - /mnt/data/config/rclone:/config/rclone
      - /mnt/data/data/gdrive-sync:/data
    command: rcd --rc-web-gui --rc-addr :5572 --rc-user admin --rc-pass \$RCLONE_PASSWORD
    ports:
      - "5572:5572"
    restart: unless-stopped
    networks:
      - aiplatform

networks:
  aiplatform:
    external: true
EOF
    
    cat > "$ENV_DIR/gdrive-sync.env" << ENV
RCLONE_PASSWORD=$(openssl rand -base64 16)
SYNC_INTERVAL=1800
ENV
}

deploy_service() {
    local service=$1
    
    log_step "Deploying $service..."
    
    # Deploy based on service
    case $service in
        dify)
            docker compose -f "$COMPOSE_DIR/dify-api.yml" up -d
            docker compose -f "$COMPOSE_DIR/dify-worker.yml" up -d
            docker compose -f "$COMPOSE_DIR/dify-web.yml" up -d
            ;;
        *)
            docker compose -f "$COMPOSE_DIR/${service}.yml" up -d
            ;;
    esac
    
    # Wait for service to be healthy
    sleep 5
    
    if docker ps | grep -q "$service"; then
        log_info "✅ $service is running"
        
        # Add to selected services
        jq --arg svc "$service" \
           '.applications += [$svc] | .applications |= unique' \
           "$METADATA_DIR/selected_services.json" > /tmp/selected_services.json.tmp
        
        mv /tmp/selected_services.json.tmp "$METADATA_DIR/selected_services.json"
        
        return 0
    else
        log_error "❌ $service failed to start"
        docker logs "$service"
        return 1
    fi
}

show_service_info() {
    local service=$1
    
    cat << EOF

╔════════════════════════════════════════════════════════════╗
║          ✅ SERVICE DEPLOYED SUCCESSFULLY                  ║
╚════════════════════════════════════════════════════════════╝

Service: $service

EOF
    
    case $service in
        open-webui)
            echo "Access at: http://$DOMAIN:8080"
            echo "Default: No authentication required"
            ;;
        anythingllm)
            echo "Access at: http://$DOMAIN:3001"
            echo "First-run setup required"
            ;;
        dify)
            echo "Access at: http://$DOMAIN:3002"
            echo "First-run setup required"
            ;;
        n8n)
            N8N_PASSWORD=$(cat "$ENV_DIR/n8n.env" | grep N8N_PASSWORD | cut -d= -f2)
            echo "Access at: http://$DOMAIN:5678"
            echo "Setup wizard on first access"
            ;;
        flowise)
            FLOWISE_PASSWORD=$(cat "$ENV_DIR/flowise.env" | grep FLOWISE_PASSWORD | cut -d= -f2)
            echo "Access at: http://$DOMAIN:3003"
            echo "Username: admin"
            echo "Password: $FLOWISE_PASSWORD"
            ;;
        comfyui)
            echo "Access at: http://$DOMAIN:8188"
            ;;
        openclaw-ui)
            echo "Access at: http://$DOMAIN:3000"
            ;;
        signal-api)
            echo "API endpoint: http://$DOMAIN:8090"
            echo "Run ./3-configure-services.sh to pair phone"
            ;;
        gdrive-sync)
            echo "Web GUI: http://$DOMAIN:5572"
            echo "Run ./3-configure-services.sh for OAuth setup"
            ;;
    esac
    
    echo
}

main() {
    show_banner
    check_prerequisites
    load_config
    
    declare -A SERVICE_OPTIONS
    
    while true; do
        show_service_catalog
        
        read -p "Select service to add (0 to exit): " choice
        
        if [ "$choice" = "0" ]; then
            log_info "Exiting..."
            exit 0
        fi
        
        selected_service="${SERVICE_OPTIONS[$choice]}"
        
        if [ -z "$selected_service" ]; then
            log_warn "Invalid selection"
            sleep 2
            continue
        fi
        
        # Check dependencies
        if ! check_dependencies "$selected_service"; then
            read -p "Press Enter to continue..."
            continue
        fi
        
        # Check port conflicts
        if ! check_port_conflicts "$selected_service"; then
            read -p "Press Enter to continue..."
            continue
        fi
        
        # Generate compose and env files
        log_step "Generating configuration for $selected_service..."
        generate_service_compose "$selected_service"
        
        # Deploy
        if deploy_service "$selected_service"; then
            show_service_info "$selected_service"
        fi
        
        read -p "Press Enter to continue..."
    done
}

main "$@"
