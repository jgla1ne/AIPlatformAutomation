#!/bin/bash

#==============================================================================
# Script 2: Service Deployment
# Purpose: Deploy core infrastructure services
# Services:
#   - PostgreSQL (database)
#   - Redis (cache/queue)
#   - Qdrant (vector database)
#   - Ollama (local LLM runtime)
#   - LiteLLM (LLM proxy/gateway)
#   - Signal API (messaging)
#   - OpenClaw (web automation)
#   - Google Drive sync
#==============================================================================

set -euo pipefail

#------------------------------------------------------------------------------
# Color Definitions
#------------------------------------------------------------------------------
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

#------------------------------------------------------------------------------
# Global Variables
#------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="/mnt/data"
METADATA_FILE="$DATA_DIR/metadata/deployment_info.json"

# Check if metadata exists
if [[ ! -f "$METADATA_FILE" ]]; then
    echo -e "${RED}Error: Setup not completed. Run script 1 first.${NC}"
    exit 1
fi

# Load metadata
DATA_DIR=$(jq -r '.data_directory' "$METADATA_FILE")
GPU_AVAILABLE=$(jq -r '.gpu_available' "$METADATA_FILE")

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------

print_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${BOLD}AI PLATFORM AUTOMATION - SERVICE DEPLOYMENT${NC}       ${CYAN}║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}Script 2 of 5${NC} - Deploying infrastructure services      ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[i]${NC} $1"
}

generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

generate_api_key() {
    echo "sk-$(openssl rand -hex 32)"
}

spinner() {
    local pid=$1
    local msg=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    echo -n "  "
    while kill -0 $pid 2>/dev/null; do
        i=$(((i + 1) % 10))
        printf "\r${CYAN}${spin:$i:1}${NC} $msg"
        sleep 0.1
    done
    printf "\r"
}

wait_for_service() {
    local service=$1
    local port=$2
    local max_wait=${3:-60}
    local elapsed=0
    
    print_info "Waiting for $service to be ready..."
    
    while ! nc -z localhost $port &>/dev/null; do
        sleep 1
        ((elapsed++))
        if [[ $elapsed -ge $max_wait ]]; then
            print_error "$service failed to start"
            return 1
        fi
        printf "\r  ${CYAN}⏳${NC} Waiting... ${elapsed}s"
    done
    printf "\r"
    print_success "$service is ready"
}

#------------------------------------------------------------------------------
# Service Selection Menu
#------------------------------------------------------------------------------

show_service_menu() {
    print_header
    echo -e "${BOLD}Select Services to Deploy${NC}"
    echo ""
    echo "Choose which services to deploy:"
    echo ""
    echo -e "${CYAN}Core Infrastructure (Required):${NC}"
    echo "  [1] PostgreSQL      - Primary database"
    echo "  [2] Redis           - Cache and message queue"
    echo "  [3] Qdrant          - Vector database"
    echo "  [4] Ollama          - Local LLM runtime"
    echo "  [5] LiteLLM         - LLM proxy/gateway"
    echo ""
    echo -e "${CYAN}Integration Services (Optional):${NC}"
    echo "  [6] Signal API      - Messaging integration"
    echo "  [7] OpenClaw        - Web automation"
    echo "  [8] Google Drive    - Cloud storage sync"
    echo ""
    echo -e "${CYAN}Quick Options:${NC}"
    echo "  [A] All services"
    echo "  [C] Core only (1-5)"
    echo "  [Q] Quit"
    echo ""
}

select_services() {
    local services=()
    
    while true; do
        show_service_menu
        read -p "Selection (comma-separated or letter): " choice
        
        choice=$(echo "$choice" | tr '[:lower:]' '[:upper:]')
        
        case $choice in
            A)
                services=(postgres redis qdrant ollama litellm signal openclaw gdrive)
                break
                ;;
            C)
                services=(postgres redis qdrant ollama litellm)
                break
                ;;
            Q)
                exit 0
                ;;
            *)
                IFS=',' read -ra selections <<< "$choice"
                for sel in "${selections[@]}"; do
                    sel=$(echo "$sel" | tr -d ' ')
                    case $sel in
                        1) services+=(postgres) ;;
                        2) services+=(redis) ;;
                        3) services+=(qdrant) ;;
                        4) services+=(ollama) ;;
                        5) services+=(litellm) ;;
                        6) services+=(signal) ;;
                        7) services+=(openclaw) ;;
                        8) services+=(gdrive) ;;
                        *) print_error "Invalid selection: $sel" ;;
                    esac
                done
                
                if [[ ${#services[@]} -gt 0 ]]; then
                    break
                fi
                ;;
        esac
    done
    
    # Remove duplicates
    services=($(echo "${services[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    
    echo ""
    print_info "Selected services: ${services[*]}"
    echo ""
    read -p "Press Enter to continue..."
    
    echo "${services[@]}"
}

#------------------------------------------------------------------------------
# PostgreSQL Deployment
#------------------------------------------------------------------------------

deploy_postgres() {
    print_step "Deploying PostgreSQL..."
    
    local postgres_password=$(generate_password)
    
    # Create environment file
    cat > "$DATA_DIR/env/postgres.env" <<EOF
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$postgres_password
POSTGRES_DB=ai_platform
PGDATA=/var/lib/postgresql/data/pgdata
EOF
    
    # Create compose file
    cat > "$DATA_DIR/compose/postgres.yml" <<EOF
version: '3.8'

services:
  postgres:
    image: postgres:16-alpine
    container_name: postgres
    restart: unless-stopped
    env_file:
      - $DATA_DIR/env/postgres.env
    volumes:
      - $DATA_DIR/postgres:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - ai-platform

networks:
  ai-platform:
    name: ai-platform
    driver: bridge
EOF
    
    # Start service
    docker compose -f "$DATA_DIR/compose/postgres.yml" up -d
    
    # Wait for service
    wait_for_service "PostgreSQL" 5432 60
    
    # Create databases for other services
    print_info "Creating databases..."
    
    docker exec postgres psql -U postgres -c "CREATE DATABASE n8n;" 2>/dev/null || true
    docker exec postgres psql -U postgres -c "CREATE DATABASE dify;" 2>/dev/null || true
    docker exec postgres psql -U postgres -c "CREATE DATABASE flowise;" 2>/dev/null || true
    docker exec postgres psql -U postgres -c "CREATE DATABASE litellm;" 2>/dev/null || true
    
    print_success "PostgreSQL deployed"
    
    # Save credentials
    save_credentials "postgres" "postgres" "$postgres_password" "5432"
}

#------------------------------------------------------------------------------
# Redis Deployment
#------------------------------------------------------------------------------

deploy_redis() {
    print_step "Deploying Redis..."
    
    local redis_password=$(generate_password)
    
    # Create environment file
    cat > "$DATA_DIR/env/redis.env" <<EOF
REDIS_PASSWORD=$redis_password
EOF
    
    # Create Redis config
    cat > "$DATA_DIR/config/redis.conf" <<EOF
requirepass $redis_password
maxmemory 2gb
maxmemory-policy allkeys-lru
appendonly yes
appendfsync everysec
save 900 1
save 300 10
save 60 10000
EOF
    
    # Create compose file
    cat > "$DATA_DIR/compose/redis.yml" <<EOF
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    container_name: redis
    restart: unless-stopped
    command: redis-server /usr/local/etc/redis/redis.conf
    volumes:
      - $DATA_DIR/redis:/data
      - $DATA_DIR/config/redis.conf:/usr/local/etc/redis/redis.conf
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
    networks:
      - ai-platform

networks:
  ai-platform:
    external: true
EOF
    
    # Start service
    docker compose -f "$DATA_DIR/compose/redis.yml" up -d
    
    # Wait for service
    wait_for_service "Redis" 6379 30
    
    print_success "Redis deployed"
    
    # Save credentials
    save_credentials "redis" "" "$redis_password" "6379"
}

#------------------------------------------------------------------------------
# Qdrant Deployment
#------------------------------------------------------------------------------

deploy_qdrant() {
    print_step "Deploying Qdrant..."
    
    local qdrant_api_key=$(generate_api_key)
    
    # Create environment file
    cat > "$DATA_DIR/env/qdrant.env" <<EOF
QDRANT__SERVICE__API_KEY=$qdrant_api_key
QDRANT__SERVICE__ENABLE_TLS=false
EOF
    
    # Create compose file
    cat > "$DATA_DIR/compose/qdrant.yml" <<EOF
version: '3.8'

services:
  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    restart: unless-stopped
    env_file:
      - $DATA_DIR/env/qdrant.env
    volumes:
      - $DATA_DIR/qdrant:/qdrant/storage
    ports:
      - "6333:6333"
      - "6334:6334"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6333/healthz"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - ai-platform

networks:
  ai-platform:
    external: true
EOF
    
    # Start service
    docker compose -f "$DATA_DIR/compose/qdrant.yml" up -d
    
    # Wait for service
    wait_for_service "Qdrant" 6333 30
    
    print_success "Qdrant deployed"
    
    # Save credentials
    save_credentials "qdrant" "" "$qdrant_api_key" "6333"
}

#------------------------------------------------------------------------------
# Ollama Deployment
#------------------------------------------------------------------------------

deploy_ollama() {
    print_step "Deploying Ollama..."
    
    local gpu_support=""
    if [[ "$GPU_AVAILABLE" == "true" ]]; then
        gpu_support=$(cat <<EOF
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
EOF
)
    fi
    
    # Create compose file
    cat > "$DATA_DIR/compose/ollama.yml" <<EOF
version: '3.8'

services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    volumes:
      - $DATA_DIR/ollama:/root/.ollama
    ports:
      - "11434:11434"
    environment:
      - OLLAMA_HOST=0.0.0.0
$gpu_support
    healthcheck:
      test: ["CMD", "ollama", "list"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - ai-platform

networks:
  ai-platform:
    external: true
EOF
    
    # Start service
    docker compose -f "$DATA_DIR/compose/ollama.yml" up -d
    
    # Wait for service
    wait_for_service "Ollama" 11434 30
    
    print_success "Ollama deployed"
    
    # Optionally pull a model
    echo ""
    if confirm "Pull llama3.2:3b model? (2GB download)" y; then
        print_info "Pulling llama3.2:3b..."
        docker exec ollama ollama pull llama3.2:3b &
        spinner $! "Downloading model..."
        wait $!
        print_success "Model downloaded"
    fi
    
    # Save info
    save_credentials "ollama" "" "" "11434"
}

#------------------------------------------------------------------------------
# LiteLLM Deployment
#------------------------------------------------------------------------------

deploy_litellm() {
    print_step "Deploying LiteLLM..."
    
    # Check if required services are running
    if ! docker ps --format '{{.Names}}' | grep -q '^postgres$'; then
        print_error "PostgreSQL not running. Deploy PostgreSQL first."
        return 1
    fi
    
    local litellm_master_key=$(generate_api_key)
    local postgres_password=$(grep POSTGRES_PASSWORD "$DATA_DIR/env/postgres.env" | cut -d'=' -f2)
    
    # Create environment file
    cat > "$DATA_DIR/env/litellm.env" <<EOF
LITELLM_MASTER_KEY=$litellm_master_key
DATABASE_URL=postgresql://postgres:$postgres_password@postgres:5432/litellm
LITELLM_LOG_LEVEL=INFO
EOF
    
    # Prompt for LLM provider configuration
    configure_litellm_providers
    
    # Create compose file
    cat > "$DATA_DIR/compose/litellm.yml" <<EOF
version: '3.8'

services:
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm
    restart: unless-stopped
    env_file:
      - $DATA_DIR/env/litellm.env
    volumes:
      - $DATA_DIR/config/litellm_config.yaml:/app/config.yaml
    ports:
      - "4000:4000"
    command: --config /app/config.yaml --port 4000 --num_workers 4
    depends_on:
      - postgres
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - ai-platform

networks:
  ai-platform:
    external: true
EOF
    
    # Start service
    docker compose -f "$DATA_DIR/compose/litellm.yml" up -d
    
    # Wait for service
    wait_for_service "LiteLLM" 4000 60
    
    print_success "LiteLLM deployed"
    print_info "Master Key: $litellm_master_key"
    
    # Save credentials
    save_credentials "litellm" "" "$litellm_master_key" "4000"
}

configure_litellm_providers() {
    echo ""
    echo -e "${BOLD}LiteLLM Provider Configuration${NC}"
    echo ""
    echo "Configure LLM providers (you can add more later):"
    echo ""
    
    local providers=()
    
    # Check for Ollama
    if docker ps --format '{{.Names}}' | grep -q '^ollama$'; then
        echo -e "${CYAN}[1] Ollama${NC} (detected)"
        providers+=("ollama")
    fi
    
    echo -e "${CYAN}[2] OpenAI${NC}"
    echo -e "${CYAN}[3] Anthropic${NC}"
    echo -e "${CYAN}[4] Google (Gemini)${NC}"
    echo -e "${CYAN}[5] Skip for now${NC}"
    echo ""
    
    read -p "Select providers (comma-separated): " selection
    
    local config_models=()
    
    IFS=',' read -ra selected <<< "$selection"
    for choice in "${selected[@]}"; do
        choice=$(echo "$choice" | tr -d ' ')
        case $choice in
            1)
                config_models+=($(cat <<EOF

  - model_name: llama3.2
    litellm_params:
      model: ollama/llama3.2:3b
      api_base: http://ollama:11434
EOF
))
                ;;
            2)
                read -p "Enter OpenAI API key: " openai_key
                config_models+=($(cat <<EOF

  - model_name: gpt-4o
    litellm_params:
      model: gpt-4o
      api_key: $openai_key
  - model_name: gpt-4o-mini
    litellm_params:
      model: gpt-4o-mini
      api_key: $openai_key
EOF
))
                ;;
            3)
                read -p "Enter Anthropic API key: " anthropic_key
                config_models+=($(cat <<EOF

  - model_name: claude-3-5-sonnet
    litellm_params:
      model: claude-3-5-sonnet-20241022
      api_key: $anthropic_key
EOF
))
                ;;
            4)
                read -p "Enter Google API key: " google_key
                config_models+=($(cat <<EOF

  - model_name: gemini-2.0-flash
    litellm_params:
      model: gemini/gemini-2.0-flash-exp
      api_key: $google_key
EOF
))
                ;;
        esac
    done
    
    # Create LiteLLM config
    cat > "$DATA_DIR/config/litellm_config.yaml" <<EOF
model_list:${config_models[@]}

litellm_settings:
  drop_params: true
  success_callback: ["langfuse"]
  failure_callback: ["langfuse"]
  
router_settings:
  routing_strategy: latency-based-routing
  model_group_alias:
    gpt-4: gpt-4o
    claude: claude-3-5-sonnet
  
general_settings:
  master_key: ${LITELLM_MASTER_KEY:-}
  database_url: ${DATABASE_URL:-}
EOF
    
    print_success "LiteLLM configuration created"
}

#------------------------------------------------------------------------------
# Signal API Deployment
#------------------------------------------------------------------------------

deploy_signal() {
    print_step "Deploying Signal API..."
    
    # Create compose file
    cat > "$DATA_DIR/compose/signal.yml" <<EOF
version: '3.8'

services:
  signal-api:
    image: bbernhard/signal-cli-rest-api:latest
    container_name: signal-api
    restart: unless-stopped
    environment:
      - MODE=json-rpc
      - AUTO_RECEIVE_SCHEDULE=*/10 * * * *
    volumes:
      - $DATA_DIR/signal:/home/.local/share/signal-cli
    ports:
      - "8090:8080"
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8080/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - ai-platform

networks:
  ai-platform:
    external: true
EOF
    
    # Start service
    docker compose -f "$DATA_DIR/compose/signal.yml" up -d
    
    # Wait for service
    wait_for_service "Signal API" 8090 30
    
    print_success "Signal API deployed"
    print_warning "Complete Signal pairing using script 3 (configure-services.sh)"
    
    # Save info
    save_credentials "signal" "" "" "8090"
}

#------------------------------------------------------------------------------
# OpenClaw Deployment
#------------------------------------------------------------------------------

deploy_openclaw() {
    print_step "Deploying OpenClaw..."
    
    # Create compose file
    cat > "$DATA_DIR/compose/openclaw.yml" <<EOF
version: '3.8'

services:
  openclaw:
    image: openclaw/openclaw:latest
    container_name: openclaw
    restart: unless-stopped
    environment:
      - DISPLAY=:99
    volumes:
      - $DATA_DIR/openclaw:/app/data
    ports:
      - "8091:8080"
      - "5900:5900"  # VNC for debugging
    shm_size: 2gb
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - ai-platform

networks:
  ai-platform:
    external: true
EOF
    
    # Start service
    docker compose -f "$DATA_DIR/compose/openclaw.yml" up -d
    
    # Wait for service
    wait_for_service "OpenClaw" 8091 60
    
    print_success "OpenClaw deployed"
    print_info "VNC available on port 5900 for debugging"
    
    # Save info
    save_credentials "openclaw" "" "" "8091"
}

#------------------------------------------------------------------------------
# Google Drive Sync Deployment
#------------------------------------------------------------------------------

deploy_gdrive() {
    print_step "Deploying Google Drive Sync..."
    
    print_info "Google Drive sync requires OAuth2 credentials"
    print_info "Setup will be completed in script 3 (configure-services.sh)"
    
    # Create placeholder compose file
    cat > "$DATA_DIR/compose/gdrive.yml" <<EOF
version: '3.8'

services:
  gdrive-sync:
    image: rclone/rclone:latest
    container_name: gdrive-sync
    restart: unless-stopped
    command: >
      rcd
      --rc-web-gui
      --rc-addr=:5572
      --rc-user=admin
      --rc-pass=changeme
    volumes:
      - $DATA_DIR/gdrive:/config
      - $DATA_DIR/gdrive/mount:/data
    ports:
      - "5572:5572"
    networks:
      - ai-platform

networks:
  ai-platform:
    external: true
EOF
    
    # Start service
    docker compose -f "$DATA_DIR/compose/gdrive.yml" up -d
    
    # Wait for service
    wait_for_service "Google Drive Sync" 5572 30
    
    print_success "Google Drive Sync deployed"
    print_warning "Complete OAuth setup using script 3"
    
    # Save info
    save_credentials "gdrive" "admin" "changeme" "5572"
}

#------------------------------------------------------------------------------
# Helper: Save Credentials
#------------------------------------------------------------------------------

save_credentials() {
    local service=$1
    local username=$2
    local password=$3
    local port=$4
    
    local creds_file="$DATA_DIR/metadata/credentials.json"
    
    if [[ ! -f "$creds_file" ]]; then
        echo "{}" > "$creds_file"
    fi
    
    local temp_file=$(mktemp)
    jq --arg service "$service" \
       --arg username "$username" \
       --arg password "$password" \
       --arg port "$port" \
       '.[$service] = {username: $username, password: $password, port: $port, deployed_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))}' \
       "$creds_file" > "$temp_file"
    
    mv "$temp_file" "$creds_file"
    chmod 600 "$creds_file"
}

confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local response
    
    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
    read -r -p "$(echo -e ${YELLOW}$prompt${NC})" response
    response=${response:-$default}
    
    [[ "$response" =~ ^[Yy]$ ]]
}

#------------------------------------------------------------------------------
# Deployment Summary
#------------------------------------------------------------------------------

print_deployment_summary() {
    clear
    print_header
    
    echo -e "${GREEN}${BOLD}✓ Services Deployed Successfully!${NC}"
    echo ""
    echo -e "${BOLD}Deployed Services:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # List running services
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(postgres|redis|qdrant|ollama|litellm|signal|openclaw|gdrive)" || true
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    if [[ -f "$DATA_DIR/metadata/credentials.json" ]]; then
        echo -e "${CYAN}Important Credentials:${NC}"
        echo ""
        
        if jq -e '.litellm' "$DATA_DIR/metadata/credentials.json" &>/dev/null; then
            local litellm_key=$(jq -r '.litellm.password' "$DATA_DIR/metadata/credentials.json")
            echo -e "  ${BOLD}LiteLLM Master Key:${NC}"
            echo -e "    $litellm_key"
            echo ""
        fi
        
        echo -e "  ${YELLOW}Full credentials saved to:${NC}"
        echo -e "    $DATA_DIR/metadata/credentials.json"
        echo ""
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "${GREEN}${BOLD}Next Steps:${NC}"
    echo ""
    echo "1. Configure services (Signal pairing, LLM providers, etc):"
    echo -e "   ${CYAN}sudo ./scripts/3-configure-services.sh${NC}"
    echo ""
    echo "2. Add user-facing applications:"
    echo -e "   ${CYAN}sudo ./scripts/4-add-service.sh${NC}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

#------------------------------------------------------------------------------
# Main Function
#------------------------------------------------------------------------------

main() {
    print_header
    
    # Select services
    local services_to_deploy=($(select_services))
    
    print_header
    print_step "Starting deployment..."
    echo ""
    
    # Deploy selected services
    for service in "${services_to_deploy[@]}"; do
        case $service in
            postgres) deploy_postgres ;;
            redis) deploy_redis ;;
            qdrant) deploy_qdrant ;;
            ollama) deploy_ollama ;;
            litellm) deploy_litellm ;;
            signal) deploy_signal ;;
            openclaw) deploy_openclaw ;;
            gdrive) deploy_gdrive ;;
        esac
        echo ""
    done
    
    # Show summary
    print_deployment_summary
}

# Run main function
main "$@"
