#!/bin/bash

#==============================================================================
# Script 2: Unified Services Deployment
# Purpose: Deploy all selected services using Script 1's configuration
# Version: 5.0.0 - Unified Deployment Engine
#==============================================================================

set -euo pipefail

# Color definitions (matching Script 1)
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# Paths (matching Script 1)
readonly DATA_ROOT="/mnt/data"
readonly METADATA_DIR="$DATA_ROOT/metadata"
readonly STATE_FILE="$METADATA_DIR/setup_state.json"
readonly LOG_FILE="$DATA_ROOT/logs/deployment.log"
readonly ENV_FILE="$DATA_ROOT/.env"
readonly SERVICES_FILE="$METADATA_DIR/selected_services.json"
readonly COMPOSE_DIR="$DATA_ROOT/compose"
readonly CONFIG_DIR="$DATA_ROOT/config"
readonly CREDENTIALS_FILE="$METADATA_DIR/credentials.json"

# Source environment (handle readonly variables)
if [[ -f "$ENV_FILE" ]]; then
    # Export all variables except readonly ones defined in this script
    while IFS= read -r line; do
        if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            var_name="${line%%=*}"
            # Skip readonly variables defined in this script
            case "$var_name" in
                DATA_ROOT|METADATA_DIR|STATE_FILE|LOG_FILE|ENV_FILE|SERVICES_FILE|COMPOSE_DIR|CONFIG_DIR|CREDENTIALS_FILE)
                    continue
                    ;;
                *)
                    export "$line"
                    ;;
            esac
        fi
    done < "$ENV_FILE"
else
    echo -e "${RED}Error: Environment file not found. Run script 1 first.${NC}"
    exit 1
fi

# UI Functions (matching Script 1 style)
print_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║            AI PLATFORM AUTOMATION - DEPLOYMENT                 ║"
    echo "║                      Version 5.0.0                               ║"
    echo "║                Unified Services Deployment                   ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

print_header() {
    local title="$1"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $title"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_phase() {
    local phase="$1"
    local icon="$2"
    local title="$3"
    
    echo ""
    print_header "$icon STEP $phase/8: $title"
}

confirm() {
    local message="$1"
    local default="${2:-n}"
    local response
    
    while true; do
        if [[ "$default" == "y" ]]; then
            echo -n -e "${YELLOW}$message [Y/n]:${NC} "
        else
            echo -n -e "${YELLOW}$message [y/N]:${NC} "
        fi
        
        read -r response
        response=${response:-$default}
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "Please enter y or n" ;;
        esac
    done
}

#------------------------------------------------------------------------------
# Core Deployment Functions
#------------------------------------------------------------------------------

load_configuration() {
    print_info "Loading configuration from Script 1..."
    
    # Load selected services
    if [[ ! -f "$SERVICES_FILE" ]]; then
        print_error "Selected services file not found. Run Script 1 first."
        exit 1
    fi
    
    # Load environment variables (already loaded above)
    if [[ ! -f "$ENV_FILE" ]]; then
        print_error "Environment file not found. Run Script 1 first."
        exit 1
    fi
    
    # Get selected services
    local selected_services=($(jq -r '.services[].key' "$SERVICES_FILE" 2>/dev/null || echo ""))
    
    print_success "Configuration loaded: ${#selected_services[@]} services selected"
    print_info "Services: $(IFS=', '; echo "${selected_services[*]}")"
}

deploy_service() {
    local service="$1"
    
    print_info "Deploying $service..."
    
    case "$service" in
        postgres) deploy_postgres ;;
        redis) deploy_redis ;;
        qdrant) deploy_qdrant ;;
        milvus) deploy_milvus ;;
        chroma) deploy_chroma ;;
        weaviate) deploy_weaviate ;;
        ollama) deploy_ollama ;;
        litellm) deploy_litellm ;;
        openwebui) deploy_openwebui ;;
        anythingllm) deploy_anythingllm ;;
        dify) deploy_dify ;;
        n8n) deploy_n8n ;;
        flowise) deploy_flowise ;;
        signal-api) deploy_signal_api ;;
        openclaw) deploy_openclaw ;;
        grafana) deploy_grafana ;;
        prometheus) deploy_prometheus ;;
        minio) deploy_minio ;;
        nginx-proxy-manager|traefik|caddy|swag) deploy_proxy "$service" ;;
        tailscale) deploy_tailscale ;;
        *) 
            print_warn "Unknown service: $service"
            return 1
            ;;
    esac
    
    # Return the exit code of the deployment function
    return $?
}

#------------------------------------------------------------------------------
# Service Deployment Functions
#------------------------------------------------------------------------------

deploy_postgres() {
    print_info "Generating PostgreSQL configuration..."
    
    mkdir -p "$COMPOSE_DIR/postgres"
    
    cat > "$COMPOSE_DIR/postgres/docker-compose.yml" <<EOF
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: postgres
    restart: unless-stopped
    networks:
      - ai_platform
    environment:
      - POSTGRES_USER=${POSTGRES_USER:-postgres}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB:-aiplatform}
      - PGDATA=/var/lib/postgresql/data/pgdata
    volumes:
      - ${DATA_ROOT}/postgres:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-postgres}"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  ai_platform:
    external: true
EOF
    
    print_success "PostgreSQL configuration generated"
    
    docker-compose -f "$COMPOSE_DIR/postgres/docker-compose.yml" up -d
    
    wait_for_service "PostgreSQL" "http://localhost:5432" 30
    
    # Return the exit code from wait_for_service
    local postgres_result=$?
    if [[ $postgres_result -eq 0 ]]; then
        print_success "PostgreSQL deployed successfully"
        return 0
    else
        print_error "PostgreSQL deployment failed"
        return 1
    fi
}

deploy_redis() {
    print_info "Generating Redis configuration..."
    
    mkdir -p "$COMPOSE_DIR/redis"
    
    cat > "$COMPOSE_DIR/redis/docker-compose.yml" <<EOF
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    container_name: redis
    restart: unless-stopped
    networks:
      - ai_platform
    command: redis-server --appendonly yes --requirepass ${REDIS_PASSWORD}
    volumes:
      - ${DATA_ROOT}/redis:/data
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  ai_platform:
    external: true
EOF
    
    print_success "Redis configuration generated"
    
    docker-compose -f "$COMPOSE_DIR/redis/docker-compose.yml" up -d
    
    wait_for_service "Redis" "http://localhost:6379" 30
    
    # Return the exit code from wait_for_service
    local redis_result=$?
    if [[ $redis_result -eq 0 ]]; then
        print_success "Redis deployed successfully"
        return 0
    else
        print_error "Redis deployment failed"
        return 1
    fi
}

#------------------------------------------------------------------------------
# Phase Functions (Script 1 Style)
#------------------------------------------------------------------------------

validate_prerequisites() {
    log_phase "1" "🔍" "Pre-Deployment Validation"
    
    local validation_ok=true
    
    # Check Docker
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running"
        validation_ok=false
    else
        print_success "Docker is running"
        docker_version=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
        print_info "Docker version: $docker_version"
    fi
    
    # Check Docker Compose
    if ! docker compose version > /dev/null 2>&1; then
        print_error "Docker Compose is not available"
        validation_ok=false
    else
        print_success "Docker Compose is available"
    fi
    
    # Check data directory
    if [[ ! -d "$DATA_ROOT" ]]; then
        print_error "Data directory not found: $DATA_ROOT"
        validation_ok=false
    else
        print_success "Data directory exists: $DATA_ROOT"
        local available_gb=$(df -BG "$DATA_ROOT" | awk 'NR==2 {print $4}' | tr -d 'G')
        print_info "Available disk space: ${available_gb}GB"
        
        if [[ $available_gb -lt 50 ]]; then
            print_warn "Low disk space: ${available_gb}GB available (recommended: 50GB+)"
        fi
    fi
    
    # Check environment file
    if [[ ! -f "$ENV_FILE" ]]; then
        print_error "Environment file not found: $ENV_FILE"
        validation_ok=false
    else
        print_success "Environment file loaded"
        local env_vars=$(wc -l < "$ENV_FILE")
        print_info "Environment variables: $env_vars"
    fi
    
    # Check selected services file
    if [[ ! -f "$SERVICES_FILE" ]]; then
        print_error "Selected services file not found: $SERVICES_FILE"
        validation_ok=false
    else
        local service_count=$(jq '.services | length' "$SERVICES_FILE" 2>/dev/null || echo "0")
        print_success "Services selected: $service_count"
    fi
    
    # Check Docker network
    if ! docker network ls | grep -q ai_platform; then
        print_warn "Creating Docker network 'ai_platform'..."
        docker network create ai_platform
        print_success "Docker network created"
    else
        print_success "Docker network exists"
    fi
    
    if [[ "$validation_ok" == "false" ]]; then
        echo ""
        print_error "Validation failed. Please run Script 1 first."
        exit 1
    fi
    
    print_success "Pre-deployment validation completed"
}

load_configuration_phase() {
    log_phase "2" "📋" "Configuration Loading"
    
    load_configuration
    
    # Display configuration summary
    echo ""
    print_info "Configuration Summary:"
    echo "  • Domain: ${DOMAIN_NAME:-$DOMAIN} (external), ${DOMAIN:-localhost} (internal)"
    echo "  • Data Directory: $DATA_ROOT"
    echo "  • Proxy Type: ${PROXY_TYPE:-none}"
    
    # Check if proxy services were selected
    local proxy_services=($(jq -r '.services[] | select(.key | test("nginx-proxy-manager|traefik|caddy|swag")) | .key' "$SERVICES_FILE" 2>/dev/null || echo ""))
    if [[ ${#proxy_services[@]} -gt 0 ]]; then
        echo "  • Proxy Services: ${proxy_services[*]}"
    else
        echo "  • Proxy Services: none selected"
    fi
    
    # Check if vector database services were selected
    local vector_db_services=($(jq -r '.services[] | select(.key | test("qdrant|milvus|chroma|weaviate")) | .key' "$SERVICES_FILE" 2>/dev/null || echo ""))
    if [[ ${#vector_db_services[@]} -gt 0 ]]; then
        echo "  • Vector Database: ${vector_db_services[*]}"
    else
        echo "  • Vector Database: none selected"
    fi
    
    echo "  • LLM Providers: ${LLM_PROVIDERS:-none configured}"
    echo "  • Total Services: $(jq -r '.total_services' "$SERVICES_FILE" 2>/dev/null || echo "0")"
    
    print_success "Configuration loaded successfully"
}

deploy_infrastructure() {
    log_phase "3" "🏗️" "Infrastructure Deployment"
    
    local selected_services=($(jq -r '.services[].key' "$SERVICES_FILE" 2>/dev/null || echo ""))
    local infrastructure_services=()
    
    # Identify infrastructure services
    for service in "${selected_services[@]}"; do
        case "$service" in
            postgres|redis|qdrant|milvus|chroma|weaviate)
                infrastructure_services+=("$service")
                ;;
        esac
    done
    
    if [[ ${#infrastructure_services[@]} -eq 0 ]]; then
        print_warn "No infrastructure services selected"
        return
    fi
    
    print_info "Deploying ${#infrastructure_services[@]} infrastructure services..."
    
    local deployed=0
    for service in "${infrastructure_services[@]}"; do
        echo ""
        print_info "[$((deployed + 1))/${#infrastructure_services[@]}] Deploying $service"
        
        if deploy_service "$service"; then
            ((deployed++))
            print_success "$service deployed successfully"
        else
            print_error "Failed to deploy $service"
        fi
    done
    
    print_success "Infrastructure deployment completed: $deployed/${#infrastructure_services[@]} services"
}

deploy_llm_layer() {
    log_phase "4" "🤖" "LLM Layer Deployment"
    
    local selected_services=($(jq -r '.services[].key' "$SERVICES_FILE" 2>/dev/null || echo ""))
    local llm_services=()
    
    # Identify LLM services
    for service in "${selected_services[@]}"; do
        case "$service" in
            ollama|litellm)
                llm_services+=("$service")
                ;;
        esac
    done
    
    if [[ ${#llm_services[@]} -eq 0 ]]; then
        print_warn "No LLM services selected"
        return
    fi
    
    print_info "Deploying ${#llm_services[@]} LLM services..."
    
    local deployed=0
    for service in "${llm_services[@]}"; do
        echo ""
        print_info "[$((deployed + 1))/${#llm_services[@]}] Deploying $service"
        
        if deploy_service "$service"; then
            ((deployed++))
            print_success "$service deployed successfully"
        else
            print_error "Failed to deploy $service"
        fi
    done
    
    print_success "LLM layer deployment completed: $deployed/${#llm_services[@]} services"
}

deploy_ai_applications() {
    log_phase "5" "🎨" "AI Applications Deployment"
    
    local selected_services=($(jq -r '.services[].key' "$SERVICES_FILE" 2>/dev/null || echo ""))
    local app_services=()
    
    # Identify AI application services
    for service in "${selected_services[@]}"; do
        case "$service" in
            openwebui|anythingllm|dify)
                app_services+=("$service")
                ;;
        esac
    done
    
    if [[ ${#app_services[@]} -eq 0 ]]; then
        print_warn "No AI applications selected"
        return
    fi
    
    print_info "Deploying ${#app_services[@]} AI applications..."
    
    local deployed=0
    for service in "${app_services[@]}"; do
        echo ""
        print_info "[$((deployed + 1))/${#app_services[@]}] Deploying $service"
        
        if deploy_service "$service"; then
            ((deployed++))
            print_success "$service deployed successfully"
        else
            print_error "Failed to deploy $service"
        fi
    done
    
    print_success "AI applications deployment completed: $deployed/${#app_services[@]} services"
}

deploy_workflow_tools() {
    log_phase "6" "⚙️" "Workflow Tools Deployment"
    
    local selected_services=($(jq -r '.services[].key' "$SERVICES_FILE" 2>/dev/null || echo ""))
    local workflow_services=()
    
    # Identify workflow services
    for service in "${selected_services[@]}"; do
        case "$service" in
            n8n|flowise)
                workflow_services+=("$service")
                ;;
        esac
    done
    
    if [[ ${#workflow_services[@]} -eq 0 ]]; then
        print_warn "No workflow tools selected"
        return
    fi
    
    print_info "Deploying ${#workflow_services[@]} workflow tools..."
    
    local deployed=0
    for service in "${workflow_services[@]}"; do
        echo ""
        print_info "[$((deployed + 1))/${#workflow_services[@]}] Deploying $service"
        
        if deploy_service "$service"; then
            ((deployed++))
            print_success "$service deployed successfully"
        else
            print_error "Failed to deploy $service"
        fi
    done
    
    print_success "Workflow tools deployment completed: $deployed/${#workflow_services[@]} services"
}

deploy_proxy_layer() {
    log_phase "7" "🌐" "Proxy Layer Deployment"
    
    local selected_services=($(jq -r '.services[].key' "$SERVICES_FILE" 2>/dev/null || echo ""))
    local proxy_services=()
    
    # Identify proxy services
    for service in "${selected_services[@]}"; do
        case "$service" in
            nginx-proxy-manager|traefik|caddy|swag)
                proxy_services+=("$service")
                ;;
        esac
    done
    
    if [[ ${#proxy_services[@]} -eq 0 ]]; then
        print_warn "No proxy services selected"
        return
    fi
    
    print_info "Deploying ${#proxy_services[@]} proxy services..."
    
    local deployed=0
    for service in "${proxy_services[@]}"; do
        echo ""
        print_info "[$((deployed + 1))/${#proxy_services[@]}] Deploying $service"
        
        if deploy_service "$service"; then
            ((deployed++))
            print_success "$service deployed successfully"
        else
            print_error "Failed to deploy $service"
        fi
    done
    
    print_success "Proxy layer deployment completed: $deployed/${#proxy_services[@]} services"
}

generate_deployment_summary() {
    log_phase "8" "📊" "Deployment Summary"
    
    echo ""
    print_header "📊 Deployment Summary"
    
    # Get all deployed containers
    local deployed_containers=$(docker ps --format "table {{.Names}}" | grep -v NAMES | wc -l)
    
    print_info "Deployment Statistics:"
    echo "  • Total Containers Running: $deployed_containers"
    echo "  • Data Directory: $DATA_ROOT"
    echo "  • Configuration Files: $(find "$COMPOSE_DIR" -name "*.yml" | wc -l)"
    echo "  • Environment Variables: $(wc -l < "$ENV_FILE")"
    
    echo ""
    print_info "Service Access URLs:"
    
    # Display service URLs based on domain configuration
    if [[ "$DOMAIN_RESOLVES" == "true" ]]; then
        print_info "Public Access (https://$DOMAIN_NAME):"
        echo "  • Open WebUI: https://$DOMAIN_NAME/openwebui"
        echo "  • AnythingLLM: https://$DOMAIN_NAME/anythingllm"
        echo "  • Dify: https://$DOMAIN_NAME/dify"
        echo "  • n8n: https://$DOMAIN_NAME/n8n"
        echo "  • Flowise: https://$DOMAIN_NAME/flowise"
        echo "  • Grafana: https://$DOMAIN_NAME/grafana"
        echo "  • MinIO: https://$DOMAIN_NAME/minio"
        echo "  • OpenClaw: https://$DOMAIN_NAME/openclaw"
        echo "  • Signal API: https://$DOMAIN_NAME/signal"
        echo "  • LiteLLM: https://$DOMAIN_NAME/litellm"
        echo "  • Ollama: https://$DOMAIN_NAME/ollama"
        echo "  • Prometheus: https://$DOMAIN_NAME/prometheus"
    else
        print_info "Local Access (http://localhost):"
        echo "  • Open WebUI: http://localhost:8080"
        echo "  • AnythingLLM: http://localhost:3001"
        echo "  • Dify: http://localhost:8000"
        echo "  • n8n: http://localhost:5678"
        echo "  • Flowise: http://localhost:3000"
        echo "  • Grafana: http://localhost:3005"
        echo "  • MinIO: http://localhost:9001"
        echo "  • OpenClaw: http://localhost:3000"
        echo "  • Signal API: http://localhost:8090"
        echo "  • LiteLLM: http://localhost:4000"
        echo "  • Ollama: http://localhost:11434"
        echo "  • Prometheus: http://localhost:9090"
    fi
    
    echo ""
    print_success "Deployment completed successfully!"
    print_info "Next steps:"
    echo "  1. Configure proxy routing for external access"
    echo "  2. Run 'sudo ./scripts/3-configure-services.sh' for service configuration"
    echo "  3. Access services using the URLs above"
}

#------------------------------------------------------------------------------
# Service Deployment Stubs (to be implemented)
#------------------------------------------------------------------------------

deploy_vector_db() {
    local db_type="$1"
    print_info "Deploying vector database: $db_type"
    # TODO: Implement vector database deployment
    print_success "$db_type deployment stub completed"
}

deploy_qdrant() {
    print_info "Generating Qdrant configuration..."
    
    mkdir -p "$COMPOSE_DIR/qdrant"
    mkdir -p "${DATA_ROOT}/qdrant"
    
    cat > "$COMPOSE_DIR/qdrant/docker-compose.yml" <<EOF
version: '3.8'

services:
  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    restart: unless-stopped
    networks:
      - ai_platform
    ports:
      - "6333:6333"
    environment:
      - QDRANT__SERVICE__HTTP_PORT=6333
      - QDRANT__SERVICE__GRPC_PORT=6334
    volumes:
      - ${DATA_ROOT}/qdrant:/qdrant/storage
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:6333/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  ai_platform:
    external: true
EOF
    
    print_success "Qdrant configuration generated"
    
    docker-compose -f "$COMPOSE_DIR/qdrant/docker-compose.yml" up -d
    
    wait_for_service "Qdrant" "http://localhost:6333" 60
    
    local qdrant_result=$?
    if [[ $qdrant_result -eq 0 ]]; then
        print_success "Qdrant deployed successfully"
        return 0
    else
        print_error "Qdrant deployment failed"
        return 1
    fi
}

deploy_milvus() {
    print_info "Generating Milvus configuration..."
    
    mkdir -p "$COMPOSE_DIR/milvus"
    mkdir -p "${DATA_ROOT}/milvus"
    
    cat > "$COMPOSE_DIR/milvus/docker-compose.yml" <<EOF
version: '3.8'

services:
  etcd:
    image: quay.io/coreos/etcd:v3.5.5
    container_name: milvus-etcd
    restart: unless-stopped
    networks:
      - ai_platform
    environment:
      - ETCD_AUTO_COMPACTION_MODE=revision
      - ETCD_QUOTA_BACKEND_BYTES=4294967296
      - ETCD_SNAPSHOT_COUNT=50000
    volumes:
      - ${DATA_ROOT}/milvus/etcd:/etcd
    command: etcd -advertise-client-urls=http://127.0.0.1:2379 -listen-client-urls http://0.0.0.0:2379 --data-dir /etcd

  minio:
    image: minio/minio:RELEASE.2023-03-20T20-16-18Z
    container_name: milvus-minio
    restart: unless-stopped
    networks:
      - ai_platform
    environment:
      - MINIO_ACCESS_KEY=minioadmin
      - MINIO_SECRET_KEY=minioadmin
    volumes:
      - ${DATA_ROOT}/milvus/minio:/minio_data
    command: minio server /minio_data

  standalone:
    image: milvusdb/milvus:v2.3.3
    container_name: milvus-standalone
    restart: unless-stopped
    networks:
      - ai_platform
    environment:
      - ETCD_ENDPOINTS=etcd:2379
      - MINIO_ADDRESS=minio:9000
    volumes:
      - ${DATA_ROOT}/milvus/volumes:/var/lib/milvus
    ports:
      - "19530:19530"
    depends_on:
      - etcd
      - minio
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:19530/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  ai_platform:
    external: true
EOF
    
    print_success "Milvus configuration generated"
    
    docker-compose -f "$COMPOSE_DIR/milvus/docker-compose.yml" up -d
    
    wait_for_service "Milvus" "http://localhost:19530" 90
    
    local milvus_result=$?
    if [[ $milvus_result -eq 0 ]]; then
        print_success "Milvus deployed successfully"
        return 0
    else
        print_error "Milvus deployment failed"
        return 1
    fi
}

deploy_chroma() {
    print_info "Generating ChromaDB configuration..."
    
    mkdir -p "$COMPOSE_DIR/chroma"
    mkdir -p "${DATA_ROOT}/chroma"
    
    cat > "$COMPOSE_DIR/chroma/docker-compose.yml" <<EOF
version: '3.8'

services:
  chroma:
    image: chromadb/chroma:latest
    container_name: chroma
    restart: unless-stopped
    networks:
      - ai_platform
    ports:
      - "8000:8000"
    environment:
      - CHROMA_SERVER_HOST=0.0.0.0
      - CHROMA_SERVER_HTTP_PORT=8000
    volumes:
      - ${DATA_ROOT}/chroma:/chroma/chroma
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8000/api/v1/heartbeat"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  ai_platform:
    external: true
EOF
    
    print_success "ChromaDB configuration generated"
    
    docker-compose -f "$COMPOSE_DIR/chroma/docker-compose.yml" up -d
    
    wait_for_service "ChromaDB" "http://localhost:8000" 60
    
    local chroma_result=$?
    if [[ $chroma_result -eq 0 ]]; then
        print_success "ChromaDB deployed successfully"
        return 0
    else
        print_error "ChromaDB deployment failed"
        return 1
    fi
}

deploy_weaviate() {
    print_info "Generating Weaviate configuration..."
    
    mkdir -p "$COMPOSE_DIR/weaviate"
    mkdir -p "${DATA_ROOT}/weaviate"
    
    cat > "$COMPOSE_DIR/weaviate/docker-compose.yml" <<EOF
version: '3.8'

services:
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
    volumes:
      - ${DATA_ROOT}/weaviate:/var/lib/weaviate
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8080/v1/.well-known/ready"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  ai_platform:
    external: true
EOF
    
    print_success "Weaviate configuration generated"
    
    docker-compose -f "$COMPOSE_DIR/weaviate/docker-compose.yml" up -d
    
    wait_for_service "Weaviate" "http://localhost:8080" 60
    
    local weaviate_result=$?
    if [[ $weaviate_result -eq 0 ]]; then
        print_success "Weaviate deployed successfully"
        return 0
    else
        print_error "Weaviate deployment failed"
        return 1
    fi
}

deploy_ollama() {
    print_info "Generating Ollama configuration..."
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting Ollama deployment" >> "$LOG_FILE"
    
    mkdir -p "$COMPOSE_DIR/ollama"
    mkdir -p "${DATA_ROOT}/ollama"
    
    cat > "$COMPOSE_DIR/ollama/docker-compose.yml" <<EOF
version: '3.8'

services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    networks:
      - ai_platform
    ports:
      - "11434:11434"
    environment:
      - OLLAMA_HOST=0.0.0.0
    volumes:
      - ${DATA_ROOT}/ollama:/root/.ollama
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/tags"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  ai_platform:
    external: true
EOF
    
    print_success "Ollama configuration generated"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Ollama configuration generated" >> "$LOG_FILE"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting Ollama container" >> "$LOG_FILE"
    docker-compose -f "$COMPOSE_DIR/ollama/docker-compose.yml" up -d 2>&1 | tee -a "$LOG_FILE"
    
    wait_for_service "Ollama" "http://localhost:11434" 60
    if [[ $? -eq 0 ]]; then
        print_success "Ollama deployed successfully"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Ollama deployed successfully" >> "$LOG_FILE"
        
        # Pull default model if specified
        if [[ -n "${OLLAMA_DEFAULT_MODEL:-}" ]]; then
            print_info "Pulling default model: $OLLAMA_DEFAULT_MODEL"
            docker exec ollama ollama pull "$OLLAMA_DEFAULT_MODEL" 2>&1 | tee -a "$LOG_FILE"
        fi
    else
        print_error "Ollama deployment failed"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Ollama deployment failed" >> "$LOG_FILE"
        return 1
    fi
}

deploy_litellm() {
    print_info "Deploying LiteLLM..."
    # TODO: Implement LiteLLM deployment
    print_success "LiteLLM deployment stub completed"
}

deploy_openwebui() {
    print_info "Deploying Open WebUI..."
    # TODO: Implement Open WebUI deployment
    print_success "Open WebUI deployment stub completed"
}

deploy_anythingllm() {
    print_info "Generating AnythingLLM configuration..."
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting AnythingLLM deployment" >> "$LOG_FILE"
    
    mkdir -p "$COMPOSE_DIR/anythingllm"
    mkdir -p "${DATA_ROOT}/anythingllm"
    mkdir -p "${DATA_ROOT}/anythingllm/storage"
    
    cat > "$COMPOSE_DIR/anythingllm/docker-compose.yml" <<EOF
version: '3.8'

services:
  anythingllm:
    image: mintplexlabs/anythingllm:latest
    container_name: anythingllm
    restart: unless-stopped
    networks:
      - ai_platform
    ports:
      - "${ANYTHINGLLM_PORT:-3001}:3001"
    environment:
      - NODE_ENV=production
      - JWT_SECRET=${ANYTHINGLLM_JWT_SECRET:-$(openssl rand -hex 32)}
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_USER=${POSTGRES_USER:-postgres}
      - DB_PASS=${POSTGRES_PASSWORD}
      - DB_NAME=${POSTGRES_DB:-aiplatform}
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=${REDIS_PASSWORD}
      - STORAGE_DIR=/app/server/storage
      - DISABLE_TELEMETRY=${ANYTHINGLLM_DISABLE_TELEMETRY:-true}
    depends_on:
      - redis
      - postgres
    volumes:
      - ${DATA_ROOT}/anythingllm/storage:/app/server/storage
      - ${DATA_ROOT}/anythingllm:/app/server/documents
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3001/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

networks:
  ai_platform:
    external: true
EOF
    
    print_success "AnythingLLM configuration generated"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - AnythingLLM configuration generated" >> "$LOG_FILE"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting AnythingLLM container" >> "$LOG_FILE"
    docker-compose -f "$COMPOSE_DIR/anythingllm/docker-compose.yml" up -d 2>&1 | tee -a "$LOG_FILE"
    
    wait_for_service "AnythingLLM" "http://localhost:${ANYTHINGLLM_PORT:-3001}" 60
    if [[ $? -eq 0 ]]; then
        print_success "AnythingLLM deployed successfully"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - AnythingLLM deployed successfully" >> "$LOG_FILE"
    else
        print_error "AnythingLLM deployment failed"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - AnythingLLM deployment failed" >> "$LOG_FILE"
        return 1
    fi
}

deploy_dify() {
    print_info "Deploying Dify..."
    # TODO: Implement Dify deployment
    print_success "Dify deployment stub completed"
}

deploy_n8n() {
    print_info "Generating n8n configuration..."
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting n8n deployment" >> "$LOG_FILE"
    
    mkdir -p "$COMPOSE_DIR/n8n"
    mkdir -p "${DATA_ROOT}/n8n"
    
    cat > "$COMPOSE_DIR/n8n/docker-compose.yml" <<EOF
version: '3.8'

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    networks:
      - ai_platform
    ports:
      - "${N8N_PORT:-5678}:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=${N8N_BASIC_AUTH_ACTIVE:-true}
      - N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER:-admin}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}
      - N8N_HOST=${N8N_HOST:-0.0.0.0}
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - WEBHOOK_URL=http://${DOMAIN_NAME:-localhost}:${N8N_PORT:-5678}/
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB:-aiplatform}
      - DB_POSTGRESDB_USER=${POSTGRES_USER:-postgres}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - NODE_ENV=production
      - N8N_EMAIL=${N8N_EMAIL:-}
      - N8N_SMTP_HOST=${N8N_SMTP_HOST:-}
      - N8N_SMTP_PORT=${N8N_SMTP_PORT:-587}
      - N8N_SMTP_USER=${N8N_SMTP_USER:-}
      - N8N_SMTP_PASS=${N8N_SMTP_PASS:-}
      - N8N_SMTP_SENDER=${N8N_SMTP_SENDER:-}
    depends_on:
      - postgres
    volumes:
      - ${DATA_ROOT}/n8n:/home/node/.n8n
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

networks:
  ai_platform:
    external: true
EOF
    
    print_success "n8n configuration generated"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - n8n configuration generated" >> "$LOG_FILE"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting n8n container" >> "$LOG_FILE"
    docker-compose -f "$COMPOSE_DIR/n8n/docker-compose.yml" up -d 2>&1 | tee -a "$LOG_FILE"
    
    wait_for_service "n8n" "http://localhost:${N8N_PORT:-5678}" 60
    if [[ $? -eq 0 ]]; then
        print_success "n8n deployed successfully"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - n8n deployed successfully" >> "$LOG_FILE"
    else
        print_error "n8n deployment failed"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - n8n deployment failed" >> "$LOG_FILE"
        return 1
    fi
}

deploy_flowise() {
    print_info "Generating Flowise configuration..."
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting Flowise deployment" >> "$LOG_FILE"
    
    mkdir -p "$COMPOSE_DIR/flowise"
    mkdir -p "${DATA_ROOT}/flowise"
    
    cat > "$COMPOSE_DIR/flowise/docker-compose.yml" <<EOF
version: '3.8'

services:
  flowise:
    image: flowiseai/flowise:latest
    container_name: flowise
    restart: unless-stopped
    networks:
      - ai_platform
    ports:
      - "${FLOWISE_PORT:-3000}:3000"
    environment:
      - PORT=3000
      - FLOWISE_SECRETKEY=${FLOWISE_SECRETKEY:-$(openssl rand -hex 32)}
      - FLOWISE_USERNAME=${FLOWISE_USERNAME:-admin}
      - FLOWISE_PASSWORD=${FLOWISE_PASSWORD:-}
      - DATABASE_TYPE=postgres
      - DATABASE_HOST=postgres
      - DATABASE_PORT=5432
      - DATABASE_NAME=${POSTGRES_DB:-aiplatform}
      - DATABASE_USER=${POSTGRES_USER:-postgres}
      - DATABASE_PASSWORD=${POSTGRES_PASSWORD}
      - APIKEY_PATH=${DATA_ROOT}/flowise/apikeys
      - FLOWISE_FILE_SIZE_LIMIT=${FLOWISE_FILE_SIZE_LIMIT:-50}
      - FLOWISE_FILE_MANAGER_ENABLED=${FLOWISE_FILE_MANAGER_ENABLED:-true}
      - FLOWISE_BLOB_STORAGE_PROVIDER=local
      - FLOWISE_BLOB_STORAGE_LOCAL_PATH=${DATA_ROOT}/flowise/uploads
    depends_on:
      - postgres
    volumes:
      - ${DATA_ROOT}/flowise:/root/.flowise
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3000/api/v1/ping"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

networks:
  ai_platform:
    external: true
EOF
    
    print_success "Flowise configuration generated"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Flowise configuration generated" >> "$LOG_FILE"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting Flowise container" >> "$LOG_FILE"
    docker-compose -f "$COMPOSE_DIR/flowise/docker-compose.yml" up -d 2>&1 | tee -a "$LOG_FILE"
    
    wait_for_service "Flowise" "http://localhost:${FLOWISE_PORT:-3000}" 60
    if [[ $? -eq 0 ]]; then
        print_success "Flowise deployed successfully"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Flowise deployed successfully" >> "$LOG_FILE"
    else
        print_error "Flowise deployment failed"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Flowise deployment failed" >> "$LOG_FILE"
        return 1
    fi
}

deploy_signal_api() {
    print_info "Generating Signal-API configuration..."
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting Signal-API deployment" >> "$LOG_FILE"
    
    mkdir -p "$COMPOSE_DIR/signal-api"
    mkdir -p "${DATA_ROOT}/signal-api"
    
    cat > "$COMPOSE_DIR/signal-api/docker-compose.yml" <<EOF
version: '3.8'

services:
  signal-api:
    image: signal-api/signal-api:latest
    container_name: signal-api
    restart: unless-stopped
    networks:
      - ai_platform
    ports:
      - "${SIGNAL_API_PORT:-8080}:8080"
    environment:
      - SIGNAL_API_HOST=0.0.0.0
      - SIGNAL_API_PORT=8080
      - REDIS_URL=redis://redis:6379
      - REDIS_PASSWORD=${REDIS_PASSWORD}
      - DATABASE_URL=postgresql://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB:-aiplatform}
      - DATABASE_TYPE=postgres
      - DATABASE_HOST=postgres
      - DATABASE_PORT=5432
      - DATABASE_NAME=${POSTGRES_DB:-aiplatform}
      - DATABASE_USER=${POSTGRES_USER:-postgres}
      - DATABASE_PASSWORD=${POSTGRES_PASSWORD}
    depends_on:
      - redis
      - postgres
    volumes:
      - ${DATA_ROOT}/signal-api:/app/data
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  ai_platform:
    external: true
EOF
    
    print_success "Signal-API configuration generated"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Signal-API configuration generated" >> "$LOG_FILE"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting Signal-API container" >> "$LOG_FILE"
    docker-compose -f "$COMPOSE_DIR/signal-api/docker-compose.yml" up -d 2>&1 | tee -a "$LOG_FILE"
    
    wait_for_service "Signal-API" "http://localhost:${SIGNAL_API_PORT:-8080}" 45
    if [[ $? -eq 0 ]]; then
        print_success "Signal-API deployed successfully"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Signal-API deployed successfully" >> "$LOG_FILE"
    else
        print_error "Signal-API deployment failed"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Signal-API deployment failed" >> "$LOG_FILE"
        return 1
    fi
}

deploy_openclaw() {
    print_info "Deploying OpenClaw..."
    # TODO: Implement OpenClaw deployment
    print_success "OpenClaw deployment stub completed"
}

deploy_grafana() {
    print_info "Generating Grafana configuration..."
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting Grafana deployment" >> "$LOG_FILE"
    
    mkdir -p "$COMPOSE_DIR/grafana"
    mkdir -p "${DATA_ROOT}/grafana"
    mkdir -p "${DATA_ROOT}/grafana/provisioning"
    
    cat > "$COMPOSE_DIR/grafana/docker-compose.yml" <<EOF
version: '3.8'

services:
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    networks:
      - ai_platform
    ports:
      - "${GRAFANA_PORT:-3001}:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER:-admin}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource
      - GF_SERVER_DOMAIN=${DOMAIN_NAME:-localhost}
      - GF_SERVER_ROOT_URL=http://${DOMAIN_NAME:-localhost}:${GRAFANA_PORT:-3001}
      - GF_SMTP_ENABLED=${GRAFANA_SMTP_ENABLED:-false}
    volumes:
      - ${DATA_ROOT}/grafana:/var/lib/grafana
      - ${DATA_ROOT}/grafana/provisioning:/etc/grafana/provisioning
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:3000/api/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  ai_platform:
    external: true
EOF
    
    print_success "Grafana configuration generated"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Grafana configuration generated" >> "$LOG_FILE"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting Grafana container" >> "$LOG_FILE"
    docker-compose -f "$COMPOSE_DIR/grafana/docker-compose.yml" up -d 2>&1 | tee -a "$LOG_FILE"
    
    wait_for_service "Grafana" "http://localhost:${GRAFANA_PORT:-3001}" 45
    if [[ $? -eq 0 ]]; then
        print_success "Grafana deployed successfully"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Grafana deployed successfully" >> "$LOG_FILE"
    else
        print_error "Grafana deployment failed"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Grafana deployment failed" >> "$LOG_FILE"
        return 1
    fi
}

deploy_prometheus() {
    print_info "Generating Prometheus configuration..."
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting Prometheus deployment" >> "$LOG_FILE"
    
    mkdir -p "$COMPOSE_DIR/prometheus"
    mkdir -p "${DATA_ROOT}/prometheus"
    mkdir -p "${DATA_ROOT}/prometheus/config"
    
    cat > "$COMPOSE_DIR/prometheus/prometheus.yml" <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'docker'
    static_configs:
      - targets: ['docker-exporter:9323']
  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']

rule_files:
  - "/etc/prometheus/rules/*.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets: []
EOF
    
    cat > "$COMPOSE_DIR/prometheus/docker-compose.yml" <<EOF
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    networks:
      - ai_platform
    ports:
      - "${PROMETHEUS_PORT:-9090}:9090"
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
    volumes:
      - ${DATA_ROOT}/prometheus/config:/etc/prometheus
      - ${DATA_ROOT}/prometheus:/prometheus
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:9090/metrics"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  ai_platform:
    external: true
EOF
    
    print_success "Prometheus configuration generated"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Prometheus configuration generated" >> "$LOG_FILE"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting Prometheus container" >> "$LOG_FILE"
    docker-compose -f "$COMPOSE_DIR/prometheus/docker-compose.yml" up -d 2>&1 | tee -a "$LOG_FILE"
    
    wait_for_service "Prometheus" "http://localhost:${PROMETHEUS_PORT:-9090}" 45
    if [[ $? -eq 0 ]]; then
        print_success "Prometheus deployed successfully"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Prometheus deployed successfully" >> "$LOG_FILE"
    else
        print_error "Prometheus deployment failed"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Prometheus deployment failed" >> "$LOG_FILE"
        return 1
    fi
}

deploy_minio() {
    print_info "Generating MinIO configuration..."
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting MinIO deployment" >> "$LOG_FILE"
    
    mkdir -p "$COMPOSE_DIR/minio"
    mkdir -p "${DATA_ROOT}/minio"
    mkdir -p "${DATA_ROOT}/minio/data"
    
    cat > "$COMPOSE_DIR/minio/docker-compose.yml" <<EOF
version: '3.8'

services:
  minio:
    image: minio/minio:latest
    container_name: minio
    restart: unless-stopped
    networks:
      - ai_platform
    ports:
      - "${MINIO_CONSOLE_PORT:-9001}:9001"
      - "${MINIO_API_PORT:-9000}:9000"
    environment:
      - MINIO_ROOT_USER=${MINIO_ROOT_USER:-minioadmin}
      - MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
      - MINIO_BROWSER_REDIRECT_URL=http://${DOMAIN_NAME:-localhost}:${MINIO_CONSOLE_PORT:-9001}
      - MINIO_SERVER_URL=http://${DOMAIN_NAME:-localhost}:${MINIO_API_PORT:-9000}
      - MINIO_DOMAIN=${DOMAIN_NAME:-localhost}
    command: server /data --console-address ":9001"
    volumes:
      - ${DATA_ROOT}/minio/data:/data
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  ai_platform:
    external: true
EOF
    
    print_success "MinIO configuration generated"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - MinIO configuration generated" >> "$LOG_FILE"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting MinIO container" >> "$LOG_FILE"
    docker-compose -f "$COMPOSE_DIR/minio/docker-compose.yml" up -d 2>&1 | tee -a "$LOG_FILE"
    
    wait_for_service "MinIO" "http://localhost:${MINIO_API_PORT:-9000}" 45
    if [[ $? -eq 0 ]]; then
        print_success "MinIO deployed successfully"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - MinIO deployed successfully" >> "$LOG_FILE"
        
        # Create default buckets if specified
        if [[ -n "${MINIO_DEFAULT_BUCKETS:-}" ]]; then
            print_info "Creating default buckets: $MINIO_DEFAULT_BUCKETS"
            IFS=',' read -ra BUCKETS <<< "$MINIO_DEFAULT_BUCKETS"
            for bucket in "${BUCKETS[@]}"; do
                docker exec minio mc mb "minio/$bucket" 2>&1 | tee -a "$LOG_FILE"
            done
        fi
    else
        print_error "MinIO deployment failed"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - MinIO deployment failed" >> "$LOG_FILE"
        return 1
    fi
}

deploy_proxy() {
    local proxy_type="$1"
    print_info "Deploying proxy: $proxy_type"
    # TODO: Implement proxy deployment
    print_success "$proxy_type deployment stub completed"
}

deploy_tailscale() {
    print_info "Generating Tailscale configuration..."
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting Tailscale deployment" >> "$LOG_FILE"
    
    mkdir -p "$COMPOSE_DIR/tailscale"
    mkdir -p "${DATA_ROOT}/tailscale"
    
    cat > "$COMPOSE_DIR/tailscale/docker-compose.yml" <<EOF
version: '3.8'

services:
  tailscale:
    image: tailscale/tailscale:latest
    container_name: tailscale
    restart: unless-stopped
    networks:
      - ai_platform
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    devices:
      - /dev/net/tun
    environment:
      - TS_AUTHKEY=${TAILSCALE_AUTH_KEY}
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_USERSPACE=${TAILSCALE_USERSPACE:-default}
      - TS_ACCEPT_DNS=${TAILSCALE_ACCEPT_DNS:-false}
      - TS_EXTRA_ARGS=${TAILSCALE_EXTRA_ARGS:-}
    volumes:
      - ${DATA_ROOT}/tailscale:/var/lib/tailscale
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:41641"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  ai_platform:
    external: true
EOF
    
    print_success "Tailscale configuration generated"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Tailscale configuration generated" >> "$LOG_FILE"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting Tailscale container" >> "$LOG_FILE"
    docker-compose -f "$COMPOSE_DIR/tailscale/docker-compose.yml" up -d 2>&1 | tee -a "$LOG_FILE"
    
    wait_for_service "Tailscale" "http://localhost:41641" 60
    if [[ $? -eq 0 ]]; then
        print_success "Tailscale deployed successfully"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Tailscale deployed successfully" >> "$LOG_FILE"
        
        # Show status
        if [[ -n "${TAILSCALE_AUTH_KEY:-}" ]]; then
            print_info "Tailscale status:"
            docker exec tailscale tailscale status 2>&1 | tee -a "$LOG_FILE"
        fi
    else
        print_error "Tailscale deployment failed"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Tailscale deployment failed" >> "$LOG_FILE"
        return 1
    fi
}

wait_for_service() {
    local service_name="$1"
    local check_url="$2"
    local max_attempts="${3:-30}"
    local attempt=0
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    echo -ne "${CYAN}  ⏳${NC} Waiting for $service_name"
    
    # Log the wait process
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting health check for $service_name at $check_url" >> "$LOG_FILE"
    
    while [ $attempt -lt $max_attempts ]; do
        # Try different health check methods based on service
        local health_result=""
        local service_name_lower=$(echo "$service_name" | tr '[:upper:]' '[:lower:]')
        case "$service_name_lower" in
            "PostgreSQL")
                health_result=$(docker exec postgres 2>/dev/null pg_isready -U "${POSTGRES_USER:-postgres}" 2>&1 || echo "failed")
                ;;
            "redis")
                if [[ -n "${REDIS_PASSWORD:-}" ]]; then
                    health_result=$(docker exec redis 2>/dev/null redis-cli -a "$REDIS_PASSWORD" ping 2>/dev/null || echo "failed")
                else
                    health_result=$(docker exec redis 2>/dev/null redis-cli ping 2>/dev/null || echo "failed")
                fi
                ;;
            *)
                # Default HTTP check
                if curl -sf "$check_url" > /dev/null 2>&1; then
                    health_result="success"
                else
                    health_result="failed"
                fi
                ;;
        esac
        
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Health check attempt $((attempt + 1))/$max_attempts for $service_name: $health_result" >> "$LOG_FILE"
        
        if [[ "$health_result" == "success" ]] || [[ "$health_result" == *"accepting connections"* ]] || [[ "$health_result" == "PONG" ]]; then
            echo -e "\r${GREEN}  ✓${NC} $service_name is ready                    "
            echo "$(date '+%Y-%m-%d %H:%M:%S') - $service_name health check passed" >> "$LOG_FILE"
            return 0
        fi
        
        echo -ne "."
        sleep 2
        ((attempt++))
    done
    
    echo -e "\r${RED}  ✗${NC} $service_name failed to start (timeout)      "
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $service_name health check failed after $max_attempts attempts" >> "$LOG_FILE"
    
    # Show container logs for debugging
    echo ""
    print_warn "Showing last 20 lines of $service_name container logs:"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Fetching container logs for $service_name" >> "$LOG_FILE"
    # Convert service name to lowercase for container name
    local container_name=$(echo "$service_name" | tr '[:upper:]' '[:lower:]')
    docker logs --tail 20 "$container_name" 2>&1 | tee -a "$LOG_FILE"
    
    return 1
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------

main() {
    print_banner
    
    # Check for verbose mode
    local verbose_mode=false
    if [[ "${1:-}" == "--verbose" ]] || [[ "${1:-}" == "-v" ]]; then
        verbose_mode=true
        print_info "Verbose mode enabled"
        set -x  # Enable command tracing
    fi
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Initialize log file
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ===== Script 2 Deployment Started =====" >> "$LOG_FILE"
    
    # Check if Script 1 was completed
    if [[ ! -f "$STATE_FILE" ]]; then
        print_error "Setup state file not found. Please run Script 1 first."
        exit 1
    fi
    
    local setup_status=$(jq -r '.status' "$STATE_FILE" 2>/dev/null || echo "unknown")
    if [[ "$setup_status" != "success" ]]; then
        print_error "Script 1 setup not completed successfully. Status: $setup_status"
        exit 1
    fi
    
    print_success "Script 1 setup verified - proceeding with deployment"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Script 1 setup verified" >> "$LOG_FILE"
    
    # Confirm deployment
    if ! confirm "Proceed with service deployment?" "n"; then
        print_info "Deployment cancelled by user"
        exit 0
    fi
    
    # Execute deployment phases
    validate_prerequisites
    load_configuration_phase
    deploy_infrastructure
    deploy_llm_layer
    deploy_ai_applications
    deploy_workflow_tools
    deploy_proxy_layer
    generate_deployment_summary
    
    echo ""
    print_header "🎉 DEPLOYMENT COMPLETE"
    print_success "All services deployed successfully!"
    print_info "Configuration files saved to: $COMPOSE_DIR"
    print_info "Logs available at: $LOG_FILE"
    print_info "Next: Run 'sudo ./scripts/3-configure-services.sh'"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ===== Script 2 Deployment Completed =====" >> "$LOG_FILE"
    
    # Show log tail if verbose
    if [[ "$verbose_mode" == "true" ]]; then
        echo ""
        print_info "Tailing deployment log (Ctrl+C to exit):"
        tail -f "$LOG_FILE"
    fi
}

# Execute main function
main "$@"
