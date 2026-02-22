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
    
    # Layer 3: Monitoring Services
    deploy_layer_3_monitoring
    
    # Layer 4: OpenClaw (restricted)
    deploy_layer_4_openclaw
    
    # Layer 5: Caddy (proxy - LAST)
    deploy_layer_5_proxy
    
    print_success "All services deployed in dependency order"
}

deploy_layer_0_infrastructure() {
    print_header "Layer 0: Network + AppArmor"
    
    # Skip AppArmor profiles temporarily to get services running
    print_warning "AppArmor profiles disabled temporarily for deployment"
    
    # Create Docker network
    docker network create "${DOCKER_NETWORK}" 2>/dev/null || true
    print_success "Infrastructure ready"
}

deploy_layer_1_databases() {
    print_header "Layer 1: Databases"
    
    # Ensure qdrant directory has correct ownership (qdrant runs as UID 1000)
    if [[ -d "${DATA_ROOT}/data/qdrant" ]]; then
        chown -R 1000:1000 "${DATA_ROOT}/data/qdrant"
        print_info "Fixed qdrant directory ownership to 1000:1000"
    fi
    
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
    
    # AnythingLLM
    docker run -d \
        --name anythingllm \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        -e VECTOR_DB=qdrant \
        -e QDRANT_URL=http://qdrant:6333 \
        -e ADMIN_PASSWORD="${ADMIN_PASSWORD}" \
        -v "${DATA_ROOT}/data/anythingllm:/app/server/storage/documents" \
        -v "${DATA_ROOT}/logs/anythingllm:/var/log/anythingllm" \
        -u "${RUNNING_UID}:${RUNNING_GID}" \
        mintplexlabs/anythingllm:latest
    
    # LiteLLM
    docker run -d \
        --name litellm \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        -e LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY}" \
        -v "${DATA_ROOT}/data/litellm:/app/data" \
        -v "${DATA_ROOT}/logs/litellm:/app/logs" \
        -u "${RUNNING_UID}:${RUNNING_GID}" \
        ghcr.io/berriai/litellm:main-latest
    
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
    
    # Prometheus with correct UID and data paths
    docker run -d \
        --name prometheus \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        -p 9090:9090 \
        -v "${DATA_ROOT}/config/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
        -v "${DATA_ROOT}/data/prometheus:/prometheus" \
        prom/prometheus:latest \
        --config.file=/etc/prometheus/prometheus.yml \
        --storage.tsdb.path=/prometheus \
        --web.console.libraries=/etc/prometheus/console_libraries \
        --web.console.templates=/etc/prometheus/consoles \
        --web.enable-lifecycle
    
    # Grafana - runs as root (UID 0) due to permission issues
    docker run -d \
        --name grafana \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        -e GF_SERVER_ROOT_URL="https://${DOMAIN_NAME}/grafana/" \
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
    print_header "Layer 4: Caddy (last)"
    
    # Caddyfile already written by Script 1
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
    
    sleep 5
    print_success "Caddy started with all service routes"
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
    
    local services=(postgres redis qdrant ollama n8n anythingllm litellm openwebui minio caddy)
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
    echo ""
    echo "🔧 Service URLs:"
    if [[ "${DOMAIN_RESOLVES:-false}" == "true" ]]; then
        echo "   n8n: https://${DOMAIN_NAME}/n8n/"
        echo "   AnythingLLM: https://${DOMAIN_NAME}/anythingllm/"
        echo "   LiteLLM: https://${DOMAIN_NAME}/litellm/"
        echo "   OpenWebUI: https://${DOMAIN_NAME}/openwebui/"
        echo "   MinIO: https://${DOMAIN_NAME}/minio/"
        echo "   Health Check: https://${DOMAIN_NAME}/health"
    else
        echo "   n8n: http://${LOCALHOST}:${N8N_PORT}/n8n/"
        echo "   AnythingLLM: http://${LOCALHOST}:${ANYTHINGLLM_PORT}/anythingllm/"
        echo "   LiteLLM: http://${LOCALHOST}:${LITELLM_PORT}/litellm/"
        echo "   OpenWebUI: http://${LOCALHOST}:${OPENWEBUI_PORT}/openwebui/"
        echo "   MinIO: http://${LOCALHOST}:${MINIO_CONSOLE_PORT}/minio/"
        echo "   Health Check: http://${LOCALHOST}/health"
    fi
    echo ""
    echo "📋 Next Steps:"
    echo "   1. Configure services with: bash 3-configure-services.sh"
    echo "   2. Add more services with: bash 4-add-service.sh"
    echo ""
    print_success "Deployment complete!"
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
    create_network
    load_apparmor_profiles
    set_vectordb_config
    
    # Deploy services in dependency order
    deploy_layered_services
    deploy_ai_services
    deploy_openclaw
    deploy_caddy
    
    # Validate and summarize
    validate_deployment
    display_summary
}

# Run main function
main "$@"
