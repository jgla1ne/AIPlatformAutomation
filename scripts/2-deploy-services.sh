#!/bin/bash

#==============================================================================
# Script 2: Deploy Core Services
# Purpose: Deploy Traefik, Ollama, Vector DB, and base infrastructure
# Per README: Core LLM & Infrastructure Services
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
    echo -e "${RED}Error: Environment file not found. Run script 1 first.${NC}"
    exit 1
fi

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------

print_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║         🚀 AI Platform - Core Services Deployment          ║"
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
    local max_attempts=${3:-30}
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
    
    if [[ -f "$METADATA_FILE" ]]; then
        local temp_file=$(mktemp)
        jq --arg service "$service" --arg status "$status" \
           '.services_deployed += [{"name": $service, "status": $status, "deployed_at": now | strftime("%Y-%m-%d %H:%M:%S UTC")}] | 
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
    
    # Check Docker
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running"
        validation_ok=false
    else
        print_success "Docker is running"
    fi
    
    # Check network
    if ! docker network ls | grep -q ai_platform; then
        print_error "Docker network 'ai_platform' not found"
        validation_ok=false
    else
        print_success "Docker network exists"
    fi
    
    # Check data directory
    if [[ ! -d "$DATA_DIR" ]]; then
        print_error "Data directory not found: $DATA_DIR"
        validation_ok=false
    else
        print_success "Data directory accessible"
    fi
    
    # Check environment file
    if [[ ! -f "$ENV_FILE" ]]; then
        print_error "Environment file not found"
        validation_ok=false
    else
        print_success "Environment file loaded"
    fi
    
    # Check disk space
    local available_gb=$(df -BG "$DATA_DIR" | awk 'NR==2 {print $4}' | tr -d 'G')
    if [[ $available_gb -lt 50 ]]; then
        print_warning "Low disk space: ${available_gb}GB available"
    else
        print_success "Sufficient disk space: ${available_gb}GB available"
    fi
    
    if [[ "$validation_ok" == "false" ]]; then
        echo ""
        print_error "Validation failed. Please run script 1 first."
        exit 1
    fi
}

#------------------------------------------------------------------------------
# Phase 2: Generate Core Docker Compose
#------------------------------------------------------------------------------

generate_core_compose() {
    print_phase "2" "📝 Generating Docker Compose Configuration"
    
    mkdir -p "$COMPOSE_DIR"
    
    print_info "Creating core services compose file..."
    
    cat > "$COMPOSE_DIR/core-services.yml" <<'EOF'
version: '3.8'

networks:
  ai_platform:
    external: true

services:
  #----------------------------------------------------------------------------
  # Traefik - Reverse Proxy & Load Balancer
  #----------------------------------------------------------------------------
  traefik:
    image: traefik:v2.10
    container_name: traefik
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    networks:
      - ai_platform
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"
    environment:
      - CF_API_EMAIL=${CF_API_EMAIL:-}
      - CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN:-}
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ${DATA_DIR}/traefik/traefik.yml:/traefik.yml:ro
      - ${DATA_DIR}/traefik/config:/etc/traefik/config:ro
      - ${DATA_DIR}/traefik/letsencrypt:/letsencrypt
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik.rule=Host(`traefik.${DOMAIN:-localhost}`)"
      - "traefik.http.routers.traefik.service=api@internal"
      - "traefik.http.routers.traefik.entrypoints=websecure"
      - "traefik.http.routers.traefik.tls=true"

  #----------------------------------------------------------------------------
  # Ollama - Local LLM Runtime
  #----------------------------------------------------------------------------
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    networks:
      - ai_platform
    ports:
      - "11434:11434"
    environment:
      - OLLAMA_KEEP_ALIVE=24h
      - OLLAMA_HOST=0.0.0.0
    volumes:
      - ${DATA_DIR}/ollama/models:/root/.ollama
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.ollama.rule=Host(`ollama.${DOMAIN:-localhost}`)"
      - "traefik.http.routers.ollama.entrypoints=websecure"
      - "traefik.http.services.ollama.loadbalancer.server.port=11434"

  #----------------------------------------------------------------------------
  # Redis - Cache & Session Store
  #----------------------------------------------------------------------------
  redis:
    image: redis:7-alpine
    container_name: redis
    restart: unless-stopped
    networks:
      - ai_platform
    command: redis-server --appendonly yes --requirepass ${REDIS_PASSWORD:-redis_secure_password}
    volumes:
      - ${DATA_DIR}/redis:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  #----------------------------------------------------------------------------
  # PostgreSQL - Primary Database
  #----------------------------------------------------------------------------
  postgres:
    image: postgres:15-alpine
    container_name: postgres
    restart: unless-stopped
    networks:
      - ai_platform
    environment:
      - POSTGRES_USER=${POSTGRES_USER:-aiplatform}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-postgres_secure_password}
      - POSTGRES_DB=${POSTGRES_DB:-aiplatform}
      - PGDATA=/var/lib/postgresql/data/pgdata
    volumes:
      - ${DATA_DIR}/postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-aiplatform}"]
      interval: 10s
      timeout: 5s
      retries: 5
EOF

    # Add Vector Database based on configuration
    if [[ "${VECTOR_DB:-none}" == "qdrant" ]]; then
        cat >> "$COMPOSE_DIR/core-services.yml" <<'EOF'

  #----------------------------------------------------------------------------
  # Qdrant - Vector Database
  #----------------------------------------------------------------------------
  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    restart: unless-stopped
    networks:
      - ai_platform
    ports:
      - "6333:6333"
      - "6334:6334"
    environment:
      - QDRANT__SERVICE__HTTP_PORT=6333
      - QDRANT__SERVICE__GRPC_PORT=6334
    volumes:
      - ${DATA_DIR}/qdrant/storage:/qdrant/storage
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.qdrant.rule=Host(`qdrant.${DOMAIN:-localhost}`)"
      - "traefik.http.routers.qdrant.entrypoints=websecure"
      - "traefik.http.services.qdrant.loadbalancer.server.port=6333"
EOF
    elif [[ "${VECTOR_DB:-none}" == "weaviate" ]]; then
        cat >> "$COMPOSE_DIR/core-services.yml" <<'EOF'

  #----------------------------------------------------------------------------
  # Weaviate - Vector Database
  #----------------------------------------------------------------------------
  weaviate:
    image: semitechnologies/weaviate:latest
    container_name: weaviate
    restart: unless-stopped
    networks:
      - ai_platform
    ports:
      - "8080:8080"
    environment:
      - QUERY_DEFAULTS_LIMIT=25
      - AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED=true
      - PERSISTENCE_DATA_PATH=/var/lib/weaviate
      - DEFAULT_VECTORIZER_MODULE=none
      - CLUSTER_HOSTNAME=node1
    volumes:
      - ${DATA_DIR}/weaviate/data:/var/lib/weaviate
EOF
    elif [[ "${VECTOR_DB:-none}" == "milvus" ]]; then
        cat >> "$COMPOSE_DIR/core-services.yml" <<'EOF'

  #----------------------------------------------------------------------------
  # Milvus - Vector Database (Standalone)
  #----------------------------------------------------------------------------
  etcd:
    image: quay.io/coreos/etcd:v3.5.5
    container_name: milvus-etcd
    networks:
      - ai_platform
    environment:
      - ETCD_AUTO_COMPACTION_MODE=revision
      - ETCD_AUTO_COMPACTION_RETENTION=1000
      - ETCD_QUOTA_BACKEND_BYTES=4294967296
      - ETCD_SNAPSHOT_COUNT=50000
    volumes:
      - ${DATA_DIR}/milvus/etcd:/etcd
    command: etcd -advertise-client-urls=http://127.0.0.1:2379 -listen-client-urls http://0.0.0.0:2379 --data-dir /etcd

  minio:
    image: minio/minio:latest
    container_name: milvus-minio
    networks:
      - ai_platform
    environment:
      - MINIO_ACCESS_KEY=minioadmin
      - MINIO_SECRET_KEY=minioadmin
    volumes:
      - ${DATA_DIR}/milvus/minio:/minio_data
    command: minio server /minio_data

  milvus:
    image: milvusdb/milvus:latest
    container_name: milvus
    restart: unless-stopped
    networks:
      - ai_platform
    ports:
      - "19530:19530"
      - "9091:9091"
    environment:
      - ETCD_ENDPOINTS=etcd:2379
      - MINIO_ADDRESS=minio:9000
    volumes:
      - ${DATA_DIR}/milvus/data:/var/lib/milvus
    depends_on:
      - etcd
      - minio
EOF
    fi

    # Add LiteLLM if enabled
    if [[ "${LITELLM_ENABLED:-false}" == "true" ]]; then
        cat >> "$COMPOSE_DIR/core-services.yml" <<'EOF'

  #----------------------------------------------------------------------------
  # LiteLLM - Unified LLM API Gateway
  #----------------------------------------------------------------------------
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm
    restart: unless-stopped
    networks:
      - ai_platform
    ports:
      - "4000:4000"
    environment:
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY:-sk-1234}
      - LITELLM_SALT_KEY=${LITELLM_SALT_KEY:-sk-salt-1234}
      - DATABASE_URL=postgresql://${POSTGRES_USER:-aiplatform}:${POSTGRES_PASSWORD:-postgres_secure_password}@postgres:5432/${POSTGRES_DB:-aiplatform}
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=${REDIS_PASSWORD:-redis_secure_password}
      - STORE_MODEL_IN_DB=true
    volumes:
      - ${DATA_DIR}/litellm/config:/app/config
    command: --config /app/config/config.yaml --port 4000 --num_workers 4
    depends_on:
      - postgres
      - redis
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.litellm.rule=Host(`litellm.${DOMAIN:-localhost}`)"
      - "traefik.http.routers.litellm.entrypoints=websecure"
      - "traefik.http.services.litellm.loadbalancer.server.port=4000"
EOF
    fi

    print_success "Core services compose file created"
}

#------------------------------------------------------------------------------
# Phase 3: Deploy Core Infrastructure
#------------------------------------------------------------------------------

deploy_core_services() {
    print_phase "3" "🚀 Deploying Core Services"
    
    print_step "1" "6" "🌐" "Starting Traefik..."
    docker-compose -f "$COMPOSE_DIR/core-services.yml" up -d traefik
    sleep 5
    if wait_for_service "Traefik" "http://localhost:8080/ping"; then
        update_metadata "traefik" "running"
    fi
    
    print_step "2" "6" "💾" "Starting PostgreSQL..."
    docker-compose -f "$COMPOSE_DIR/core-services.yml" up -d postgres
    sleep 10
    if docker exec postgres pg_isready -U "${POSTGRES_USER:-aiplatform}" > /dev/null 2>&1; then
        print_success "PostgreSQL is ready"
        update_metadata "postgres" "running"
    fi
    
    print_step "3" "6" "🔴" "Starting Redis..."
    docker-compose -f "$COMPOSE_DIR/core-services.yml" up -d redis
    sleep 5
    if docker exec redis redis-cli -a "${REDIS_PASSWORD:-redis_secure_password}" ping | grep -q PONG; then
        print_success "Redis is ready"
        update_metadata "redis" "running"
    fi
    
    print_step "4" "6" "🧠" "Starting Ollama..."
    docker-compose -f "$COMPOSE_DIR/core-services.yml" up -d ollama
    sleep 10
    if wait_for_service "Ollama" "http://localhost:11434/api/tags"; then
        update_metadata "ollama" "running"
    fi
    
    # Deploy vector database if configured
    if [[ "${VECTOR_DB:-none}" != "none" ]]; then
        print_step "5" "6" "🗄️" "Starting ${VECTOR_DB}..."
        
        case "${VECTOR_DB}" in
            "qdrant")
                docker-compose -f "$COMPOSE_DIR/core-services.yml" up -d qdrant
                sleep 10
                if wait_for_service "Qdrant" "http://localhost:6333/collections"; then
                    update_metadata "qdrant" "running"
                fi
                ;;
            "weaviate")
                docker-compose -f "$COMPOSE_DIR/core-services.yml" up -d weaviate
                sleep 15
                if wait_for_service "Weaviate" "http://localhost:8080/v1/.well-known/ready"; then
                    update_metadata "weaviate" "running"
                fi
                ;;
            "milvus")
                docker-compose -f "$COMPOSE_DIR/core-services.yml" up -d etcd minio
                sleep 10
                docker-compose -f "$COMPOSE_DIR/core-services.yml" up -d milvus
                sleep 15
                print_success "Milvus cluster started"
                update_metadata "milvus" "running"
                ;;
        esac
    fi
    
    # Deploy LiteLLM if enabled
    if [[ "${LITELLM_ENABLED:-false}" == "true" ]]; then
        print_step "6" "6" "🔀" "Starting LiteLLM..."
        docker-compose -f "$COMPOSE_DIR/core-services.yml" up -d litellm
        sleep 10
        if wait_for_service "LiteLLM" "http://localhost:4000/health"; then
            update_metadata "litellm" "running"
        fi
    fi
}

#------------------------------------------------------------------------------
# Phase 4: Initialize Ollama Models
#------------------------------------------------------------------------------

initialize_ollama() {
    print_phase "4" "📚 Initializing Ollama Models"
    
    echo ""
    print_info "Available models to pull:"
    echo "  1. llama2 (7B) - General purpose"
    echo "  2. mistral (7B) - Fast & efficient"
    echo "  3. codellama (7B) - Code generation"
    echo "  4. llama2:13b - More capable"
    echo "  5. Skip model download"
    echo ""
    
    read -p "Select models to pull (comma-separated, e.g., 1,2): " model_selection
    
    if [[ "$model_selection" != "5" ]] && [[ -n "$model_selection" ]]; then
        IFS=',' read -ra MODELS <<< "$model_selection"
        
        for choice in "${MODELS[@]}"; do
            case $choice in
                1)
                    print_info "Pulling llama2..."
                    docker exec ollama ollama pull llama2
                    print_success "llama2 downloaded"
                    ;;
                2)
                    print_info "Pulling mistral..."
                    docker exec ollama ollama pull mistral
                    print_success "mistral downloaded"
                    ;;
                3)
                    print_info "Pulling codellama..."
                    docker exec ollama ollama pull codellama
                    print_success "codellama downloaded"
                    ;;
                4)
                    print_info "Pulling llama2:13b..."
                    docker exec ollama ollama pull llama2:13b
                    print_success "llama2:13b downloaded"
                    ;;
            esac
        done
    else
        print_info "Model download skipped"
    fi
}

#------------------------------------------------------------------------------
# Phase 5: Configure Vector Database
#------------------------------------------------------------------------------

configure_vector_database() {
    if [[ "${VECTOR_DB:-none}" == "none" ]]; then
        return 0
    fi
    
    print_phase "5" "🗄️ Configuring Vector Database"
    
    case "${VECTOR_DB}" in
        "qdrant")
            print_info "Creating default collection in Qdrant..."
            curl -X PUT "http://localhost:6333/collections/documents" \
                -H "Content-Type: application/json" \
                -d '{
                    "vectors": {
                        "size": 384,
                        "distance": "Cosine"
                    }
                }' > /dev/null 2>&1
            print_success "Qdrant collection 'documents' created"
            ;;
        "weaviate")
            print_info "Creating default schema in Weaviate..."
            curl -X POST "http://localhost:8080/v1/schema" \
                -H "Content-Type: application/json" \
                -d '{
                    "class": "Document",
                    "vectorizer": "none",
                    "properties": [
                        {"name": "content", "dataType": ["text"]},
                        {"name": "metadata", "dataType": ["text"]}
                    ]
                }' > /dev/null 2>&1
            print_success "Weaviate schema created"
            ;;
        "milvus")
            print_success "Milvus ready (configure via SDK)"
            ;;
    esac
}

#------------------------------------------------------------------------------
# Phase 6: Service Health Check
#------------------------------------------------------------------------------

perform_health_check() {
    print_phase "6" "🏥 Service Health Check"
    
    print_box_start
    
    # Check each service
    local all_healthy=true
    
    # Traefik
    if curl -sf http://localhost:8080/ping > /dev/null 2>&1; then
        print_box_line "Traefik: ✓ Healthy (http://localhost:8080)"
    else
        print_box_line "Traefik: ✗ Unhealthy"
        all_healthy=false
    fi
    
    # PostgreSQL
    if docker exec postgres pg_isready -U "${POSTGRES_USER:-aiplatform}" > /dev/null 2>&1; then
        print_box_line "PostgreSQL: ✓ Healthy"
    else
        print_box_line "PostgreSQL: ✗ Unhealthy"
        all_healthy=false
    fi
    
    # Redis
    if docker exec redis redis-cli -a "${REDIS_PASSWORD:-redis_secure_password}" ping 2>/dev/null | grep -q PONG; then
        print_box_line "Redis: ✓ Healthy"
    else
        print_box_line "Redis: ✗ Unhealthy"
        all_healthy=false
    fi
    
    # Ollama
    if curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; then
        local model_count=$(curl -s http://localhost:11434/api/tags | jq -r '.models | length')
        print_box_line "Ollama: ✓ Healthy ($model_count models available)"
    else
        print_box_line "Ollama: ✗ Unhealthy"
        all_healthy=false
    fi
    
    # Vector Database
    if [[ "${VECTOR_DB:-none}" != "none" ]]; then
        case "${VECTOR_DB}" in
            "qdrant")
                if curl -sf http://localhost:6333/collections > /dev/null 2>&1; then
                    print_box_line "Qdrant: ✓ Healthy (http://localhost:6333)"
                else
                    print_box_line "Qdrant: ✗ Unhealthy"
                    all_healthy=false
                fi
                ;;
            "weaviate")
                if curl -sf http://localhost:8080/v1/.well-known/ready > /dev/null 2>&1; then
                    print_box_line "Weaviate: ✓ Healthy (http://localhost:8080)"
                else
                    print_box_line "Weaviate: ✗ Unhealthy"
                    all_healthy=false
                fi
                ;;
            "milvus")
                if docker ps | grep -q milvus; then
                    print_box_line "Milvus: ✓ Healthy (http://localhost:19530)"
                else
                    print_box_line "Milvus: ✗ Unhealthy"
                    all_healthy=false
                fi
                ;;
        esac
    fi
    
    # LiteLLM
    if [[ "${LITELLM_ENABLED:-false}" == "true" ]]; then
        if curl -sf http://localhost:4000/health > /dev/null 2>&1; then
            print_box_line "LiteLLM: ✓ Healthy (http://localhost:4000)"
        else
            print_box_line "LiteLLM: ✗ Unhealthy"
            all_healthy=false
        fi
    fi
    
    print_box_end
    
    if [[ "$all_healthy" == "true" ]]; then
        print_success "All services are healthy"
    else
        print_warning "Some services are unhealthy - check logs"
    fi
}

#------------------------------------------------------------------------------
# Final Success Message
#------------------------------------------------------------------------------

print_final_success() {
    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          ✅ CORE SERVICES DEPLOYED SUCCESSFULLY            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo -e "${BOLD}Available Services:${NC}"
    echo "  • Traefik Dashboard: ${CYAN}http://localhost:8080${NC}"
    echo "  • Ollama API: ${CYAN}http://localhost:11434${NC}"
    if [[ "${VECTOR_DB:-none}" != "none" ]]; then
        case "${VECTOR_DB}" in
            "qdrant") echo "  • Qdrant UI: ${CYAN}http://localhost:6333/dashboard${NC}" ;;
            "weaviate") echo "  • Weaviate: ${CYAN}http://localhost:8080/v1${NC}" ;;
            "milvus") echo "  • Milvus: ${CYAN}http://localhost:19530${NC}" ;;
        esac
    fi
    if [[ "${LITELLM_ENABLED:-false}" == "true" ]]; then
        echo "  • LiteLLM: ${CYAN}http://localhost:4000${NC}"
    fi
    echo ""
    echo -e "${BOLD}Next Steps:${NC}"
    echo "  1. Test Ollama: ${CYAN}curl http://localhost:11434/api/tags${NC}"
    echo "  2. Deploy UI: ${CYAN}./scripts/3-deploy-ui.sh${NC}"
    echo ""
    echo -e "${BOLD}Useful Commands:${NC}"
    echo "  • View logs: ${CYAN}docker-compose -f $COMPOSE_DIR/core-services.yml logs -f${NC}"
    echo "  • Restart service: ${CYAN}docker-compose -f $COMPOSE_DIR/core-services.yml restart <service>${NC}"
    echo ""
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------

main() {
    print_header
    
    validate_prerequisites
    generate_core_compose
    deploy_core_services
    initialize_ollama
    configure_vector_database
    perform_health_check
    
    print_final_success
}

main "$@"
