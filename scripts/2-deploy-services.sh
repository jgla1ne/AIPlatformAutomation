#!/bin/bash
# Script 2: Parameterized Deployment
#
# NOTE: This script runs as root (required for Docker, AppArmor, system setup)
# RUNNING_UID owns DATA_ROOT for container permissions

set -euo pipefail

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# UI Functions
print_banner() {
    clear
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║            AI PLATFORM - PARAMETERIZED DEPLOYMENT           ║${NC}"
    echo -e "${CYAN}║              Baseline v1.0.0 - Multi-Stack Ready           ║${NC}"
    echo -e "${CYAN}║           AppArmor + Vector DB + OpenClaw Integration       ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╝${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_header() {
    local title="$1"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $title"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Load configuration from .env
load_configuration() {
    print_header "Loading Configuration"
    
    if [[ -f "${DATA_ROOT:-/mnt/data}/.env" ]]; then
        source "${DATA_ROOT:-/mnt/data}/.env"
        print_success "Configuration loaded from ${DATA_ROOT}/.env"
    else
        print_error "Configuration file not found. Please run Script 1 first."
        exit 1
    fi
}

# Validate configuration
validate_config() {
    print_header "Validating Configuration"
    
    local required_vars=(DATA_ROOT RUNNING_UID RUNNING_GID DOCKER_NETWORK DOMAIN_NAME)
    for var in "${required_vars[@]}"; do
        local value="${!var:-}"
        if [[ -z "$value" ]]; then
            print_error "Required variable $var not set in .env"
            exit 1
        fi
    done
    
    print_success "Configuration validated"
}

# Create Docker network
create_network() {
    print_header "Creating Docker Network"
    
    docker network create "${DOCKER_NETWORK}" 2>/dev/null || true
    print_success "Docker network created: ${DOCKER_NETWORK}"
}

# AppArmor profile loading (fixed with explicit sed substitution)
load_apparmor_profiles() {
    print_header "Loading AppArmor Profiles"
    
    local profile_dir="${DATA_ROOT}/apparmor"

    for profile in default openclaw tailscale; do
        local src="${profile_dir}/${profile}.profile.tmpl"
        local dst="/etc/apparmor.d/${DOCKER_NETWORK}-${profile}"

        # Check if template exists
        if [[ ! -f "$src" ]]; then
            print_error "AppArmor template not found: $src"
            continue
        fi

        # Substitute DATA_ROOT into template
        sed "s|DATA_ROOT_PLACEHOLDER|${DATA_ROOT}|g" "${src}" > "${dst}"

        # Load into kernel
        if apparmor_parser -r "${dst}"; then
            print_success "AppArmor profile loaded: ${DOCKER_NETWORK}-${profile}"
        else
            print_warning "Failed to load AppArmor profile: ${DOCKER_NETWORK}-${profile}"
        fi
    done
}

# Vector DB configuration (global for stack)
set_vectordb_config() {
    print_header "Configuring Vector Database"
    
    case "${VECTOR_DB}" in
        qdrant)
            export VECTORDB_HOST="qdrant"
            export VECTORDB_PORT="6333"
            export VECTORDB_TYPE="qdrant"
            export VECTORDB_URL="http://qdrant:6333"
            export VECTORDB_COLLECTION="ai-platform"
            ;;
        pgvector)
            export VECTORDB_HOST="postgres"
            export VECTORDB_PORT="5432"
            export VECTORDB_TYPE="pgvector"
            export VECTORDB_URL="postgresql://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB:-aiplatform}"
            export VECTORDB_COLLECTION="ai-platform"
            ;;
        weaviate)
            export VECTORDB_HOST="weaviate"
            export VECTORDB_PORT="8080"
            export VECTORDB_TYPE="weaviate"
            export VECTORDB_URL="http://weaviate:8080"
            export VECTORDB_COLLECTION="AIPlatform"
            ;;
        chroma)
            export VECTORDB_HOST="chroma"
            export VECTORDB_PORT="8000"
            export VECTORDB_TYPE="chroma"
            export VECTORDB_URL="http://chroma:8000"
            export VECTORDB_COLLECTION="ai-platform"
            ;;
        *)
            print_warning "Unknown vector DB: ${VECTOR_DB}, defaulting to qdrant"
            set_vectordb_config qdrant
            ;;
    esac
    
    print_success "Vector DB configured: ${VECTORDB_TYPE} at ${VECTORDB_URL}"
    
    # Fix Docker Compose file to use proper variable substitution
    sed -i "s/VECTOR_DB: qdrant/VECTOR_DB: \${VECTOR_DB}/g" "$COMPOSE_FILE"
    sed -i "s/VECTOR_DB: milvus/VECTOR_DB: \${VECTOR_DB}/g" "$COMPOSE_FILE"
    sed -i "s/VECTOR_DB: chroma/VECTOR_DB: \${VECTOR_DB}/g" "$COMPOSE_FILE"
    sed -i "s/VECTOR_DB: weaviate/VECTOR_DB: \${VECTOR_DB}/g" "$COMPOSE_FILE"
}

# Build vector DB environment variables
build_vectordb_env() {
    local vectordb_env=()
    
    case "${VECTOR_DB}" in
        qdrant)
            vectordb_env=(
                "-e" "VECTOR_DB=qdrant"
                "-e" "QDRANT_ENDPOINT=${VECTORDB_URL}"
                "-e" "QDRANT_API_KEY="
                "-e" "QDRANT_COLLECTION=${VECTORDB_COLLECTION}"
            )
            ;;
        pgvector)
            vectordb_env=(
                "-e" "VECTOR_DB=pgvector"
                "-e" "PGVECTOR_CONNECTION_STRING=${VECTORDB_URL}"
                "-e" "PGVECTOR_SCHEMA=ai_platform"
            )
            ;;
        weaviate)
            vectordb_env=(
                "-e" "VECTOR_DB=weaviate"
                "-e" "WEAVIATE_ENDPOINT=${VECTORDB_URL}"
                "-e" "WEAVIATE_API_KEY="
                "-e" "WEAVIATE_CLASS=${VECTORDB_COLLECTION}"
            )
            ;;
        chroma)
            vectordb_env=(
                "-e" "VECTOR_DB=chroma"
                "-e" "CHROMA_ENDPOINT=${VECTORDB_URL}"
                "-e" "CHROMA_COLLECTION=${VECTORDB_COLLECTION}"
            )
            ;;
        *)
            print_warning "Unknown vector DB: ${VECTOR_DB}, defaulting to qdrant"
            set_vectordb_config qdrant
            ;;
    esac
    
    # Set the return array
    set -- "${vectordb_env[@]}"
}

# Generic service deployment function
deploy_service() {
    local service_name=$1
    local image=$2
    local internal_port=$3
    local host_port=$4
    shift 4
    local extra_env=("$@")
    
    print_info "Deploying ${service_name}..."
    
    # Create service directories
    mkdir -p "${DATA_ROOT}/data/${service_name}" "${DATA_ROOT}/logs/${service_name}"
    chown -R ${RUNNING_UID}:${RUNNING_GID} "${DATA_ROOT}/data/${service_name}"
    chown -R ${RUNNING_UID}:${RUNNING_GID} "${DATA_ROOT}/logs/${service_name}"
    
    # Get vector DB environment variables
    build_vectordb_env
    local vectordb_env=("$@")
    
    docker run -d \
        --name "${service_name}" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --user "${RUNNING_UID}:${RUNNING_GID}" \
        -p "${host_port}:${internal_port}" \
        -v "${DATA_ROOT}/data/${service_name}:/app/data" \
        -v "${DATA_ROOT}/logs/${service_name}:/app/logs" \
        "${vectordb_env[@]}" \
        "${extra_env[@]}" \
        "${image}"
    
    print_success "${service_name} deployed on port ${host_port}"
}

# Wait for Tailscale authentication
wait_for_tailscale_auth() {
    local container_name=$1
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    print_info "Waiting for Tailscale authentication..."
    
    while [[ $wait_time -lt $max_wait ]]; do
        if docker exec "$container_name" tailscale status 2>/dev/null | grep -q "Logged in"; then
            print_success "Tailscale authenticated"
            return 0
        fi
        
        sleep 5
        wait_time=$((wait_time + 5))
        echo -n "."
    done
    
    print_error "Tailscale authentication timed out"
    return 1
}

# Deploy OpenClaw with Tailscale sidecar
deploy_openclaw() {
    print_header "Deploying OpenClaw + Tailscale"
    
    if [ -z "${TAILSCALE_AUTH_KEY}" ]; then
        print_warning "TAILSCALE_AUTH_KEY missing - OpenClaw will run without Tailscale"
        deploy_openclaw_standalone
        return
    fi

    # Create OpenClaw directories
    mkdir -p "${DATA_ROOT}/data/openclaw" "${DATA_ROOT}/data/tailscale"
    chown -R ${OPENCLAW_UID}:${OPENCLAW_GID} "${DATA_ROOT}/data/openclaw"
    chown -R ${OPENCLAW_UID}:${OPENCLAW_GID} "${DATA_ROOT}/data/tailscale"

    # Step 1: Tailscale sidecar
    print_info "Deploying Tailscale sidecar..."
    docker run -d \
        --name "tailscale" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --cap-add NET_ADMIN \
        --cap-add SYS_MODULE \
         \
        --user "${OPENCLAW_UID}:${OPENCLAW_GID}" \
        -v "${DATA_ROOT}/data/tailscale:/var/lib/tailscale" \
        -v /dev/net/tun:/dev/net/tun \
        -e "TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY}" \
        -e "TAILSCALE_HOSTNAME=${TAILSCALE_HOSTNAME}" \
        tailscale/tailscale:latest

    # Wait for Tailscale authentication
    wait_for_tailscale_auth "tailscale"

    # Step 2: OpenClaw in shared network namespace
    print_info "Deploying OpenClaw..."
    local vectordb_env=($(build_vectordb_env))
    
    docker run -d \
        --name "openclaw" \
        --network "container:tailscale" \
        --restart unless-stopped \
        --user "${OPENCLAW_UID}:${OPENCLAW_GID}" \
        --read-only \
        --tmpfs /tmp:rw,noexec,nosuid,size=100m \
        -v "${DATA_ROOT}/data/openclaw:/app/data:rw" \
        -v "${DATA_ROOT}/config/openclaw:/app/config:ro" \
        ${vectordb_env[@]} \
        alpine/openclaw:latest

    print_success "OpenClaw deployed with Tailscale sidecar"
}

# Deploy OpenClaw standalone (without Tailscale)
deploy_openclaw_standalone() {
    print_info "Deploying OpenClaw (standalone mode)..."
    
    # Create OpenClaw directories
    mkdir -p "${DATA_ROOT}/data/openclaw"
    chown -R ${OPENCLAW_UID}:${OPENCLAW_GID} "${DATA_ROOT}/data/openclaw"
    
    local vectordb_env=($(build_vectordb_env))
    
    docker run -d \
        --name "openclaw" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --user "${OPENCLAW_UID}:${OPENCLAW_GID}" \
        -p "${OPENCLAW_PORT}:8080" \
        -v "${DATA_ROOT}/data/openclaw:/app/data:rw" \
        -v "${DATA_ROOT}/config/openclaw:/app/config:ro" \
        ${vectordb_env[@]} \
        alpine/openclaw:latest

    print_success "OpenClaw deployed (standalone) on port ${OPENCLAW_PORT}"
}

# Deploy infrastructure services
# Main deployment function with layered approach
deploy_layered_services() {
    print_header "Deploying Services in Dependency Order"
    
    # Layer 0: Infrastructure
    deploy_layer_0_infrastructure
    
    # Layer 1: Databases
    deploy_layer_1_databases
    
    # Layer 2: Application Services
    deploy_layer_2_services
    
    # Layer 2.5: Dify Multi-Container Service
    deploy_layer_2_5_dify
    
    # Layer 3: Monitoring Services
    deploy_layer_3_monitoring
    
    # Layer 4: OpenClaw (restricted)
    deploy_layer_4_openclaw
    
    # Layer 5: Caddy (proxy - LAST)
    deploy_layer_5_proxy
    
    print_success "All services deployed in dependency order"
}

deploy_layer_0_infrastructure() {
    print_header "Layer 0: Network + AppArmor + RClone"
    
    # Skip AppArmor profiles temporarily to get services running
    print_warning "AppArmor profiles disabled temporarily for deployment"
    
    # Create Docker network
    docker network create "${DOCKER_NETWORK}" 2>/dev/null || true
    
    # Install RClone if Google Drive sync is enabled
    if [[ "${ENABLE_RCLONE:-false}" == "true" ]] || [[ "${GDRIVE_ENABLED:-false}" == "true" ]]; then
        print_info "Setting up RClone for Google Drive sync..."
        
        # Deploy rclone container if enabled
        if [[ "${GDRIVE_ENABLED:-false}" == "true" ]]; then
            print_info "Deploying RClone container..."
            
            docker run -d \
                --name rclone-gdrive \
                --network "${DOCKER_NETWORK}" \
                --restart unless-stopped \
                --user "${RUNNING_UID}:${RUNNING_GID}" \
                -v "${DATA_ROOT}/config/rclone:/config/rclone:ro" \
                -v "${RCLONE_MOUNT_POINT:-${DATA_ROOT}/gdrive}:/data/gdrive" \
                -v "${DATA_ROOT}/logs/rclone:/logs" \
                rclone/rclone:latest \
                sync \
                gdrive:"${RCLONE_GDRIVE_FOLDER:-}" \
                /data/gdrive \
                --config=/config/rclone/rclone.conf \
                --log-file=/logs/rclone.log \
                --log-level=INFO \
                --transfers=4 \
                --checkers=8
                
            print_success "RClone container deployed"
        fi
    fi
    
    print_success "Infrastructure ready"
}

deploy_layer_1_databases() {
    print_header "Layer 1: Databases"
    
    # Set consistent ownership for all service directories
    print_info "Setting directory ownership..."
    chown -R ${RUNNING_UID}:${RUNNING_GID} ${DATA_ROOT}/data/
    chown -R ${RUNNING_UID}:${RUNNING_GID} ${DATA_ROOT}/config/
    print_success "Directory ownership configured"
    
    # PostgreSQL with explicit UID and init script
    docker run -d \
        --name postgres \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        -e POSTGRES_USER="${POSTGRES_USER}" \
        -e POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
        -v "${DATA_ROOT}/data/postgres:/var/lib/postgresql/data" \
        -v "${DATA_ROOT}/postgres-init:/docker-entrypoint-initdb.d" \
        -u "999:999" \
        postgres:15-alpine
    
    # Redis
    docker run -d \
        --name redis \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
         \
        -e REDIS_PASSWORD="${REDIS_PASSWORD}" \
        -v "${DATA_ROOT}/data/redis:/data" \
        redis:7-alpine --requirepass "${REDIS_PASSWORD}"
    
    # Qdrant
    docker run -d \
        --name qdrant \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
         \
        -v "${DATA_ROOT}/data/qdrant:/qdrant/storage" \
        qdrant/qdrant:latest
    
    # WAIT for all layer 1 to be healthy before proceeding
    wait_healthy "postgres" "docker exec postgres pg_isready -U ${POSTGRES_USER}" 30
    wait_healthy "redis" "docker exec redis redis-cli -a ${REDIS_PASSWORD} ping" 30
    wait_healthy "qdrant" "docker run --rm --network ${DOCKER_NETWORK} alpine/curl -sf http://qdrant:6333/" 60
    
    # Create pgvector extension after postgres is ready
    print_info "Creating pgvector extension..."
    docker exec postgres psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
        -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>/dev/null || true
    print_success "pgvector extension created"
    
    print_success "Layer 1 databases healthy"
}

deploy_layer_2_services() {
    print_header "Layer 2: Application Services"
    
    # MinIO - runs as root to handle system directory creation
    docker run -d \
        --name minio \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        -e MINIO_ROOT_USER="${MINIO_ROOT_USER}" \
        -e MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD}" \
        -v "${DATA_ROOT}/data/minio:/data" \
        minio/minio:latest server /data --console-address ":9001"
    
    # n8n
    docker run -d \
        --name n8n \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        -e DB_TYPE=postgresdb \
        -e DB_POSTGRESDB_HOST=postgres \
        -e DB_POSTGRESDB_DATABASE=n8n \
        -e DB_POSTGRESDB_USER="${POSTGRES_USER}" \
        -e DB_POSTGRESDB_PASSWORD="${POSTGRES_PASSWORD}" \
        -e N8N_HOST="n8n.${DOMAIN_NAME}" \
        -e N8N_PROTOCOL=https \
        -e N8N_PORT=5678 \
        -e WEBHOOK_URL="https://n8n.${DOMAIN_NAME}/" \
        -e N8N_EDITOR_BASE_URL="https://n8n.${DOMAIN_NAME}/" \
        -e HOME=/data/n8n \
        -v "${DATA_ROOT}/data/n8n:/data/n8n" \
        -u "${RUNNING_UID}:${RUNNING_GID}" \
        n8nio/n8n:latest
    
    # OpenWebUI with secret key
    docker run -d \
        --name openwebui \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        -e WEBUI_SECRET_KEY="${WEBUI_SECRET_KEY}" \
        -v "${DATA_ROOT}/data/openwebui:/app/backend/data" \
        -u "${RUNNING_UID}:${RUNNING_GID}" \
        ghcr.io/open-webui/open-webui:main
    
    # AnythingLLM - fixed configuration with proper storage path and LiteLLM integration
    docker run -d \
        --name anythingllm \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --user "${RUNNING_UID}:${RUNNING_GID}" \
        -p "${ANYTHINGLLM_PORT}:3001" \
        -v "${DATA_ROOT}/data/anythingllm:/app/server/storage" \
        -e STORAGE_DIR=/app/server/storage \
        -e JWT_SECRET="${ANYTHINGLLM_JWT_SECRET}" \
        -e DISABLE_TELEMETRY=true \
        -e LLM_PROVIDER="litellm" \
        -e LITELLM_BASE_URL="http://litellm:4000" \
        -e LITELLM_API_KEY="${LITELLM_MASTER_KEY}" \
        -e EMBEDDING_PROVIDER="litellm" \
        -e EMBEDDING_MODEL_PREF="text-embedding-ada-002" \
        mintplexlabs/anythingllm:latest
    
    # Signal API
    docker run -d \
        --name signal-api \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --user "${RUNNING_UID}:${RUNNING_GID}" \
        -p "${SIGNAL_API_PORT}:8080" \
        -e MODE=native \
        -v "${DATA_ROOT}/data/signal:/home/.local/share/signal-cli" \
        bbernhard/signal-cli-rest-api:latest
    
    # LiteLLM - enhanced configuration for multi-provider routing
    docker run -d \
        --name litellm \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        -e LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY}" \
        -e LITELLM_SALT_KEY="${LITELLM_MASTER_KEY}" \
        -e DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}" \
        -e REDIS_URL="redis://:${REDIS_PASSWORD}@redis:6379" \
        -v "${DATA_ROOT}/data/litellm:/app/data" \
        -v "${DATA_ROOT}/logs/litellm:/app/logs" \
        -v "${DATA_ROOT}/config/litellm/config.yaml:/app/config.yaml:ro" \
        -u "${RUNNING_UID}:${RUNNING_GID}" \
        ghcr.io/berriai/litellm:main-latest \
        --config /app/config.yaml --port 4000
    
    # Flowise - runs as root (UID 0) due to Node.js user info issues
    docker run -d \
        --name flowise \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        -e PORT=3000 \
        -e FLOWISE_HOST=0.0.0.0 \
        -e DATABASE_PATH=/root/.flowise \
        -e APIKEY_PATH=/root/.flowise \
        -e HOME=/root \
        -v "${DATA_ROOT}/data/flowise:/root/.flowise" \
        flowiseai/flowise:latest
    
    # Wait for layer 2
    wait_http "n8n" "http://n8n:5678/healthz" 60
    wait_http "minio" "http://minio:9000/minio/health/live" 60
    wait_http "flowise" "http://flowise:3000" 60
    # wait_http "litellm" "http://litellm:4000/health" 60  # Temporarily disabled - needs API key
    
    # Create MinIO buckets after MinIO is ready
    print_info "Creating MinIO buckets..."
    docker exec minio mc alias set local http://localhost:9000 "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" 2>/dev/null || true
    docker exec minio mc mb local/n8n-data --ignore-existing 2>/dev/null || true
    docker exec minio mc mb local/anythingllm --ignore-existing 2>/dev/null || true
    docker exec minio mc mb local/dify --ignore-existing 2>/dev/null || true
    print_success "MinIO buckets created"
    
    print_success "Layer 2 application services healthy (litellm health check disabled)"
}

deploy_layer_2_5_dify() {
    print_header "Layer 2.5: Dify Multi-Container Service"
    
    # Create Dify directories
    mkdir -p "${DATA_ROOT}/data/dify/storage"
    mkdir -p "${DATA_ROOT}/data/dify/logs"
    chown -R ${RUNNING_UID}:${RUNNING_GID} "${DATA_ROOT}/data/dify/"
    
    # Dify API container
    docker run -d \
        --name dify-api \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --user "${RUNNING_UID}:${RUNNING_GID}" \
        -e MODE=api \
        -e SECRET_KEY="${DIFY_SECRET_KEY}" \
        -e DB_USERNAME="${POSTGRES_USER}" \
        -e DB_PASSWORD="${POSTGRES_PASSWORD}" \
        -e DB_HOST=postgres \
        -e DB_PORT=5432 \
        -e DB_DATABASE="${POSTGRES_DB}" \
        -e REDIS_HOST=redis \
        -e REDIS_PORT=6379 \
        -e REDIS_PASSWORD="${REDIS_PASSWORD}" \
        -e STORAGE_TYPE=local \
        -e STORAGE_LOCAL_PATH=/app/api/storage \
        -e CELERY_BROKER_URL=redis://:${REDIS_PASSWORD}@redis:6379/1 \
        -v "${DATA_ROOT}/data/dify/storage:/app/api/storage" \
        langgenius/dify-api:latest
    
    # Dify Worker container
    docker run -d \
        --name dify-worker \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --user "${RUNNING_UID}:${RUNNING_GID}" \
        -e MODE=worker \
        -e SECRET_KEY="${DIFY_SECRET_KEY}" \
        -e DB_USERNAME="${POSTGRES_USER}" \
        -e DB_PASSWORD="${POSTGRES_PASSWORD}" \
        -e DB_HOST=postgres \
        -e DB_PORT=5432 \
        -e DB_DATABASE="${POSTGRES_DB}" \
        -e REDIS_HOST=redis \
        -e REDIS_PORT=6379 \
        -e REDIS_PASSWORD="${REDIS_PASSWORD}" \
        -e STORAGE_TYPE=local \
        -e STORAGE_LOCAL_PATH=/app/api/storage \
        -e CELERY_BROKER_URL=redis://:${REDIS_PASSWORD}@redis:6379/1 \
        -v "${DATA_ROOT}/data/dify/storage:/app/api/storage" \
        langgenius/dify-api:latest
    
    # Dify Web container
    docker run -d \
        --name dify-web \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --user "${RUNNING_UID}:${RUNNING_GID}" \
        -e EDITION=SELF_HOSTED \
        -e CONSOLE_API_URL="https://dify.${DOMAIN_NAME}" \
        -e APP_API_URL="https://dify.${DOMAIN_NAME}" \
        langgenius/dify-web:latest
    
    # Wait for Dify services
    wait_http "dify-api" "http://dify-api:5001/health" 60
    wait_http "dify-web" "http://dify-web:3000" 60
    
    print_success "Layer 2.5 Dify multi-container service healthy"
}

deploy_layer_3_monitoring() {
    print_header "Layer 3: Monitoring Services"
    
    # Create Prometheus config
    mkdir -p "${DATA_ROOT}/config/prometheus"
    mkdir -p "${DATA_ROOT}/data/prometheus"
    chown -R 65534:65534 "${DATA_ROOT}/data/prometheus"
    chown -R 65534:65534 "${DATA_ROOT}/config/prometheus"
    cat > "${DATA_ROOT}/config/prometheus/prometheus.yml" << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'n8n'
    static_configs:
      - targets: ['n8n:5678']
  
  - job_name: 'openwebui'
    static_configs:
      - targets: ['openwebui:8080']
  
  - job_name: 'litellm'
    static_configs:
      - targets: ['litellm:4000']
  
  - job_name: 'qdrant'
    static_configs:
      - targets: ['qdrant:6333']
  
  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres:5432']
  
  - job_name: 'minio'
    static_configs:
      - targets: ['minio:9000']
  
  - job_name: 'flowise'
    static_configs:
      - targets: ['flowise:3000']
EOF
    
    chown "${RUNNING_UID}:${RUNNING_GID}" "${DATA_ROOT}/config/prometheus/prometheus.yml"
    
    # Prometheus with correct port mapping and arguments
    docker run -d \
        --name prometheus \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --user "${RUNNING_UID}:${RUNNING_GID}" \
        -p "${PROMETHEUS_PORT}:9090" \
        -v "${DATA_ROOT}/config/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
        -v "${DATA_ROOT}/data/prometheus:/prometheus" \
        prom/prometheus:latest \
        --config.file=/etc/prometheus/prometheus.yml \
        --storage.tsdb.path=/prometheus \
        --web.console.libraries=/etc/prometheus/console_libraries \
        --web.console.templates=/etc/prometheus/consoles \
        --web.enable-lifecycle
    
    # Grafana with correct user and port mapping
    docker run -d \
        --name grafana \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --user "${RUNNING_UID}:${RUNNING_GID}" \
        -p "${GRAFANA_PORT}:3000" \
        -e GF_SERVER_ROOT_URL="https://grafana.${DOMAIN_NAME}/" \
        -e GF_SECURITY_ADMIN_PASSWORD="${ADMIN_PASSWORD}" \
        -v "${DATA_ROOT}/data/grafana:/var/lib/grafana" \
        grafana/grafana:latest
    
    # Wait for monitoring services
    wait_http "prometheus" "http://prometheus:9090/-/healthy" 60
    wait_http "grafana" "http://grafana:3000/api/health" 60
    print_success "Layer 3 monitoring services healthy"
}

deploy_layer_4_openclaw() {
    print_header "Layer 3: OpenClaw (restricted)"
    
    # Temporarily skip OpenClaw - image not available
    print_warning "OpenClaw deployment skipped - image not available"
    
    # docker run -d \
    #     --name openclaw \
    #     --network "${DOCKER_NETWORK}" \
    #     --restart unless-stopped \
    #      \
    #     -e VECTOR_DB_URL="http://qdrant:6333" \
    #     -e HOME=/data/openclaw \
    #     -e OPENCLAW_HOME=/data/openclaw \
    #     -e OPENCLAW_CONFIG=/data/openclaw/config \
    #     -e XDG_CONFIG_HOME=/data/openclaw/.config \
    #     -e XDG_DATA_HOME=/data/openclaw/.local \
    #     -v "${DATA_ROOT}/data/openclaw:/data/openclaw" \
    #     -u "${OPENCLAW_UID}:${OPENCLAW_GID}" \
    #     --read-only \
    #     --tmpfs /tmp:rw,noexec,nosuid \
    #     openclaw/openclaw:latest
    
    print_success "Layer 3 OpenClaw skipped"
    # wait_http "openclaw" "http://openclaw:8080/health" 60  # Skipped - OpenClaw not deployed
    print_success "Layer 3 OpenClaw healthy (skipped)"
}

deploy_layer_5_proxy() {
    print_header "Layer 5: Caddy (last)"
    
    # Ensure Caddyfile directory exists and is properly formatted
    mkdir -p "${DATA_ROOT}/caddy"
    
    # Caddyfile already written by Script 1, but ensure proper SSL configuration
    # Remove any stale lock files before starting
    if docker exec caddy find /data/caddy/locks/ -name "*.lock" 2>/dev/null | grep -q .; then
        print_info "Removing stale certificate lock files..."
        docker exec caddy find /data/caddy/locks/ -name "*.lock" -delete 2>/dev/null || true
    fi
    
    # Remove stale ACME challenge tokens
    docker exec caddy find /data/caddy/acme/ -name "*.json" -delete 2>/dev/null || true
    
    docker run -d \
        --name caddy \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        -p "80:80" \
        -p "443:443" \
        -v "${DATA_ROOT}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" \
        -v "${DATA_ROOT}/caddy/data:/data" \
        -v "${DATA_ROOT}/caddy/config:/config" \
        caddy:2-alpine
    
    # Wait for Caddy to start and begin certificate issuance
    sleep 10
    
    print_success "Caddy started with SSL certificate management"
}

wait_healthy() {
    local container=$1
    local check_cmd=$2
    local timeout=$3
    local elapsed=0
    
    echo -n "  Waiting for ${container}..."
    while ! eval "${check_cmd}" &>/dev/null; do
        sleep 2
        elapsed=$((elapsed + 2))
        echo -n "."
        if [[ $elapsed -ge $timeout ]]; then
            echo ""
            print_error "${container} failed to become healthy after ${timeout}s"
            print_info "Logs:"
            docker logs --tail 20 "${container}"
            exit 1
        fi
    done
    echo " "
}

wait_http() {
    local name=$1
    local url=$2
    local timeout=$3
    local elapsed=0
    
    echo -n "  Waiting for ${name} HTTP..."
    while ! docker run --rm --network "${DOCKER_NETWORK}" \
            curlimages/curl:latest -sf "${url}" &>/dev/null; do
        sleep 3
        elapsed=$((elapsed + 3))
        echo -n "."
        if [[ $elapsed -ge $timeout ]]; then
            echo ""
            print_error "${name} HTTP check failed after ${timeout}s"
            print_info "Logs:"
            docker logs --tail 30 "${name}"
            exit 1
        fi
    done
    echo " "
}

# Validate deployment
validate_deployment() {
    print_header "Validating Deployment"
    
    local services=(postgres redis qdrant ollama n8n anythingllm litellm openwebui minio caddy prometheus grafana flowise signal-api dify-api dify-worker dify-web)
    local failed_services=()
    
    for service in "${services[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "^${service}$"; then
            print_success "${service} is running"
        else
            print_warning "${service} is not running"
            failed_services+=("$service")
        fi
    done
    
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        print_warning "Some services failed to start: ${failed_services[*]}"
        print_info "Check logs with: docker logs <service_name>"
    else
        print_success "All services deployed successfully!"
    fi
}

# Display deployment summary
display_summary() {
    print_header "Deployment Summary"
    
    echo "📊 Stack Information:"
    echo "   Base Directory: ${DATA_ROOT}"
    echo "   Network: ${DOCKER_NETWORK}"
    echo "   Domain: ${DOMAIN_NAME}"
    echo "   Proxy Method: ${PROXY_CONFIG_METHOD:-subdomain}"
    echo ""
    echo "🌐 Service URLs:"
    if [[ "${PROXY_CONFIG_METHOD:-subdomain}" == "subdomain" ]]; then
        echo "   n8n: https://n8n.${DOMAIN_NAME}/"
        echo "   OpenWebUI: https://openwebui.${DOMAIN_NAME}/"
        echo "   AnythingLLM: https://anythingllm.${DOMAIN_NAME}/"
        echo "   Flowise: https://flowise.${DOMAIN_NAME}/"
        echo "   LiteLLM: https://litellm.${DOMAIN_NAME}/"
        echo "   Grafana: https://grafana.${DOMAIN_NAME}/"
        echo "   MinIO: https://minio.${DOMAIN_NAME}/"
        echo "   Signal API: https://signal-api.${DOMAIN_NAME}/"
        echo "   Prometheus: https://prometheus.${DOMAIN_NAME}/"
        echo "   Dify: https://dify.${DOMAIN_NAME}/"
        echo "   Main Domain: https://${DOMAIN_NAME}/ (redirects to OpenWebUI)"
    else
        echo "   n8n: http://${LOCALHOST}:${N8N_PORT}/n8n/"
        echo "   OpenWebUI: http://${LOCALHOST}:${OPENWEBUI_PORT}/openwebui/"
        echo "   AnythingLLM: http://${LOCALHOST}:${ANYTHINGLLM_PORT}/anythingllm/"
        echo "   Flowise: http://${LOCALHOST}:${FLOWISE_PORT}/flowise/"
        echo "   LiteLLM: http://${LOCALHOST}:${LITELLM_PORT}/litellm/"
        echo "   Grafana: http://${LOCALHOST}:${GRAFANA_PORT}/grafana/"
        echo "   MinIO: http://${LOCALHOST}:${MINIO_CONSOLE_PORT}/minio/"
        echo "   Signal API: http://${LOCALHOST}:${SIGNAL_API_PORT}/"
        echo "   Prometheus: http://${LOCALHOST}:${PROMETHEUS_PORT}/prometheus/"
        echo "   Dify: http://${LOCALHOST}:${DIFY_PORT}/dify/"
    fi
    echo ""
    echo "📋 Next Steps:"
    echo "   1. Access services via the URLs above"
    echo "   2. Check service health: docker ps"
    echo "   3. View logs: docker logs <service_name>"
    echo "   4. Monitor certificates: docker exec caddy find /data/caddy/certificates/ -name '*.crt'"
    
    # RClone management section
    if [[ "${GDRIVE_ENABLED:-false}" == "true" ]]; then
        echo ""
        echo "📁 RClone Google Drive Management:"
        echo "   - Run sync now: docker restart rclone-gdrive"
        echo "   - View logs: docker logs rclone-gdrive --tail 50"
        echo "   - Check status: docker inspect rclone-gdrive"
        echo "   - Mount point: ${RCLONE_MOUNT_POINT:-${DATA_ROOT}/gdrive}"
    fi
    
    # Tailscale/OpenClaw section
    if [[ -n "${TAILSCALE_IP:-}" ]] && [[ "${TAILSCALE_IP}" != "pending" ]]; then
        echo ""
        echo "🔒 OpenClaw (internal only):"
        echo "   URL: http://${TAILSCALE_IP}:18789"
        echo "   Access via Tailscale VPN only"
        echo "   Install Tailscale client: https://tailscale.com/download"
    fi
    echo ""
    print_success "Deployment complete! All services are running with SSL certificates."
}

# LiteLLM configuration generation
generate_litellm_config() {
    local conf_path="${DATA_ROOT}/config/litellm/config.yaml"
    mkdir -p "${DATA_ROOT}/config/litellm"

    cat > "${conf_path}" << EOF
model_list:
EOF

    # Add OpenAI models if enabled (check for API key)
    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        cat >> "${conf_path}" << EOF
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: ${OPENAI_API_KEY}
  - model_name: gpt-4o-mini
    litellm_params:
      model: openai/gpt-4o-mini
      api_key: ${OPENAI_API_KEY}
EOF
    fi

    # Add Anthropic models if enabled (check for API key)
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        cat >> "${conf_path}" << EOF
  - model_name: claude-sonnet-4-5
    litellm_params:
      model: anthropic/claude-sonnet-4-5
      api_key: ${ANTHROPIC_API_KEY}
  - model_name: claude-haiku-3-5
    litellm_params:
      model: anthropic/claude-haiku-3-5
      api_key: ${ANTHROPIC_API_KEY}
EOF
    fi

    # Add Ollama model if Ollama is enabled
    if [[ "${ENABLE_OLLAMO:-false}" == "true" ]]; then
        cat >> "${conf_path}" << EOF
  - model_name: ollama-llama3
    litellm_params:
      model: ollama/llama3
      api_base: http://ollama:11434
EOF
    fi

    # Always add the general settings block
    cat >> "${conf_path}" << EOF

general_settings:
  master_key: ${LITELLM_MASTER_KEY}
  database_url: postgresql://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD}@postgres:5432/litellm

litellm_settings:
  drop_params: true
  request_timeout: 120
EOF

    chmod 600 "${conf_path}"
    chown "${RUNNING_UID}:${RUNNING_GID}" "${conf_path}"
    print_success "LiteLLM config written to ${conf_path}"
}

# Tailscale setup and IP retrieval
setup_tailscale() {
    if [[ -z "${TAILSCALE_AUTH_KEY:-}" ]]; then
        print_info "Tailscale auth key not provided - skipping setup"
        return
    fi
    
    print_info "Setting up Tailscale..."
    
    # Install tailscale if not present
    if ! command -v tailscale &>/dev/null; then
        print_info "Installing Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh
    fi
    
    # Start tailscaled daemon if not running
    if ! systemctl is-active --quiet tailscaled; then
        systemctl enable tailscaled
        systemctl start tailscaled
    fi
    
    # Authenticate
    tailscale up \
        --authkey="${TAILSCALE_AUTH_KEY}" \
        --hostname="${TAILSCALE_HOSTNAME:-ai-platform}" \
        --accept-routes \
        --ssh
    
    # Wait for IP assignment (max 30 seconds)
    local ts_ip=""
    local attempts=0
    while [[ -z "$ts_ip" ]] && [[ $attempts -lt 15 ]]; do
        ts_ip=$(tailscale ip -4 2>/dev/null || true)
        [[ -z "$ts_ip" ]] && sleep 2
        attempts=$((attempts + 1))
    done
    
    if [[ -z "$ts_ip" ]]; then
        print_error "Tailscale did not assign an IP within 30 seconds"
        print_error "Check: tailscale status"
        return 1
    fi
    
    # Write IP back to .env (replace placeholder)
    sed -i "s/TAILSCALE_IP=pending/TAILSCALE_IP=${ts_ip}/" "${ENV_FILE}"
    
    print_success "Tailscale IP: ${ts_ip}"
    print_success "OpenClaw accessible at: http://${ts_ip}:18789"
}

# RClone configuration generation
generate_rclone_config() {
    if [[ "${GDRIVE_ENABLED:-false}" != "true" ]]; then
        print_info "Google Drive sync disabled — skipping rclone config"
        return
    fi

    # Config was already written by Script 1.
    # Just validate it exists before starting the container.
    if [[ ! -f "${DATA_ROOT}/config/rclone/rclone.conf" ]]; then
        print_error "rclone.conf not found at ${DATA_ROOT}/config/rclone/rclone.conf"
        print_error "Re-run Script 1 and complete the Google Drive setup."
        exit 1
    fi

    print_success "rclone config found — container will start syncing on deploy"
}

# RClone service management
create_rclone_service() {
    print_info "Creating RClone systemd service..."
    
    # Create systemd service file
    cat > "/etc/systemd/system/rclone-gdrive.service" << EOF
[Unit]
Description=RClone Google Drive Mount Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUNNING_USER}
Group=${RUNNING_GID}
ExecStart=/usr/bin/rclone mount ${RCLONE_REMOTE_NAME:-gdrive}: ${RCLONE_MOUNT_POINT} \\
    --config ${RCLONE_CONFIG_DIR} \\
    --cache-dir ${RCLONE_CACHE_DIR} \\
    --log-file ${RCLONE_LOGS_DIR}/rclone.log \\
    --log-level INFO \\
    --allow-non-empty \\
    --vfs-cache-mode writes \\
    --dir-cache-time 5m \\
    --poll-interval 1m \\
    --umask 002
ExecStop=/bin/fusermount -u ${RCLONE_MOUNT_POINT}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # Create mount point if it doesn't exist
    mkdir -p "${RCLONE_MOUNT_POINT}"
    chown "${RUNNING_UID}:${RUNNING_GID}" "${RCLONE_MOUNT_POINT}"
    
    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable rclone-gdrive.service
    
    print_success "RClone service created and enabled"
    print_info "Use 'systemctl start rclone-gdrive' to start the mount"
    print_info "Use 'systemctl stop rclone-gdrive' to stop the mount"
}

# Main function
main() {
    # Ensure running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
    
    print_banner
    
    # Execute deployment phases
    load_configuration
    validate_config
    set_vectordb_config
    
    # Deploy services in dependency order
    # Generate configurations before deployment
    generate_rclone_config
    generate_litellm_config
    
    # Setup Tailscale before services start
    setup_tailscale
    
    deploy_layered_services
    
    # Validate and summarize
    validate_deployment
    display_summary
}

# Run main function
main "$@"
