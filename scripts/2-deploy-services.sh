#!/bin/bash
# ==============================================================================
# Script 2: Deploy Services
# Version: 2.0 - Modular Architecture Support
# Purpose: Deploy all AI platform services using modular Docker Compose
# Usage: ./2-deploy-services.sh [--skip-build] [--service SERVICE_NAME]
# Features: Self-contained, modular compose generation, service selection
# ==============================================================================

set -euo pipefail

# ==============================================================================
# SELF-CONTAINED LOGGING FUNCTIONS
# ==============================================================================

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] ✓ $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] ⚠ $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] ✗ $*"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# ==============================================================================
# CONFIGURATION
# ==============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="${SCRIPT_DIR}/.."
readonly AI_PLATFORM_DIR="/mnt/data/ai-platform"
readonly CONFIG_DIR="${AI_PLATFORM_DIR}/config"
readonly DOCKER_DIR="${AI_PLATFORM_DIR}/docker"
readonly DATA_DIR="${AI_PLATFORM_DIR}/data"
readonly LOGS_DIR="${AI_PLATFORM_DIR}/logs"
readonly ENV_FILE="${PROJECT_ROOT}/.env"
readonly DEPLOYMENT_TIMEOUT=300
readonly HEALTH_CHECK_RETRIES=30
readonly HEALTH_CHECK_INTERVAL=10

# Command line options
SKIP_BUILD=false
SPECIFIC_SERVICE=""

# ==============================================================================
# VALIDATION FUNCTIONS
# ==============================================================================

validate_prerequisites() {
    log_step "Validating prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not available"
        return 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not available"
        return 1
    fi
    
    # Check service selection file exists
    if [[ ! -f "${CONFIG_DIR}/service-selection.env" ]]; then
        log_error "Service selection file not found. Please run script 1 first."
        return 1
    fi
    
    # Check master env file exists
    if [[ ! -f "${CONFIG_DIR}/master.env" ]]; then
        log_error "Master configuration file not found. Please run script 1 first."
        return 1
    fi
    
    log_success "Prerequisites validated"
    return 0
}

validate_service_selection() {
    log_step "Loading service selection..."
    
    # Source service selection
    source "${CONFIG_DIR}/service-selection.env"
    
    # Validate required selections
    if [[ -z "${SELECTED_PROXY:-}" ]]; then
        log_error "No proxy selected"
        return 1
    fi
    
    if [[ -z "${SELECTED_VECTOR_DB:-}" ]]; then
        log_error "No vector database selected"
        return 1
    fi
    
    log_success "Service selection loaded"
    log_info "Selected proxy: ${SELECTED_PROXY}"
    log_info "Selected vector DB: ${SELECTED_VECTOR_DB}"
    return 0
}

validate_compose_files() {
    log_step "Validating Docker Compose files..."
    
    local failed_files=()
    
    for compose_file in "${DOCKER_DIR}"/docker-compose.*.yml; do
        if [[ -f "$compose_file" ]]; then
            if docker compose -f "$compose_file" config > /dev/null 2>&1; then
                log_success "$(basename "$compose_file") is valid"
            else
                log_error "$(basename "$compose_file") validation failed"
                failed_files+=("$(basename "$compose_file")")
            fi
        fi
    done
    
    if [[ ${#failed_files[@]} -gt 0 ]]; then
        log_error "Failed compose files: ${failed_files[*]}"
        return 1
    fi
    
    log_success "All Docker Compose files are valid"
    return 0
}

# ==============================================================================
# DEPLOYMENT FUNCTIONS
# ==============================================================================

create_networks() {
    log_step "Creating Docker networks..."
    
    local networks=("ai-platform-network" "ai-backend-network")
    
    for network in "${networks[@]}"; do
        if ! docker network inspect "$network" &> /dev/null; then
            log_info "Creating network: $network"
            docker network create "$network" || {
                log_error "Failed to create network: $network"
                return 1
            }
        else
            log_info "Network $network already exists"
        fi
    done
    
    log_success "Docker networks created"
}

generate_modular_composes() {
    log_step "Generating modular Docker Compose files..."
    
    # Source service selection and hardware profile
    source "${CONFIG_DIR}/service-selection.env"
    source "${CONFIG_DIR}/hardware-profile.env"
    
    # Create Docker directory
    mkdir -p "${DOCKER_DIR}"
    
    # Generate core infrastructure compose files
    generate_postgres_compose
    generate_redis_compose
    generate_litellm_compose
    generate_proxy_compose
    
    # Generate vector database compose file
    case "$SELECTED_VECTOR_DB" in
        qdrant) generate_qdrant_compose ;;
        chromadb) generate_chromadb_compose ;;
        redis) generate_redis_vector_compose ;;
        weaviate) generate_weaviate_compose ;;
    esac
    
    # Generate AI service compose files
    for service in "${SELECTED_AI_SERVICES[@]}"; do
        case "$service" in
            dify) generate_dify_compose ;;
            n8n) generate_n8n_compose ;;
            open-webui) generate_openwebui_compose ;;
            flowise) generate_flowise_compose ;;
            anythingllm) generate_anythingllm_compose ;;
            openclaw) generate_openclaw_compose ;;
        esac
    done
    
    # Generate optional service compose files
    for service in "${SELECTED_OPTIONAL_SERVICES[@]}"; do
        case "$service" in
            monitoring) generate_monitoring_compose ;;
            minio) generate_minio_compose ;;
            development) generate_development_compose ;;
            supertokens) generate_supertokens_compose ;;
            signal) generate_signal_compose ;;
            tailscale) generate_tailscale_compose ;;
        esac
    done
    
    log_success "Modular compose files generated"
}

# ==============================================================================
# COMPOSE GENERATION FUNCTIONS
# ==============================================================================

generate_postgres_compose() {
    cat > "${DOCKER_DIR}/docker-compose.postgres.yml" << EOF
version: '3.8'

services:
  postgres:
    image: postgres:16-alpine
    container_name: ai-platform-postgres
    restart: unless-stopped
    networks:
      - ai-backend-network
    ports:
      - "127.0.0.1:\${POSTGRES_PORT:-5432}:5432"
    environment:
      POSTGRES_DB: aiplatform
      POSTGRES_USER: aiplatform
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_INITDB_ARGS: "--encoding=UTF-8 --lc-collate=C --lc-ctype=C"
    volumes:
      - ${DATA_DIR}/postgresql:/var/lib/postgresql/data
      - ${CONFIG_DIR}/postgres:/docker-entrypoint-initdb.d
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER} -d \${POSTGRES_DB}"]
      interval: 30s
      timeout: 10s
      retries: 5
    deploy:
      resources:
        limits:
          memory: \${POSTGRES_MEM_LIMIT:-2g}
        reservations:
          memory: \${POSTGRES_MEM_RESERVATION:-1g}
    logging:
      driver: "json-file"
      options:
        max-file: "3"
        max-size: "10m"

networks:
  ai-backend-network:
    driver: bridge
EOF
}

generate_redis_compose() {
    cat > "${DOCKER_DIR}/docker-compose.redis.yml" << EOF
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    container_name: ai-platform-redis
    restart: unless-stopped
    networks:
      - ai-backend-network
    ports:
      - "127.0.0.1:\${REDIS_PORT:-6379}:6379"
    command: redis-server --appendonly yes --requirepass \${REDIS_PASSWORD}
    volumes:
      - ${DATA_DIR}/redis:/data
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 30s
      timeout: 10s
      retries: 5
    deploy:
      resources:
        limits:
          memory: \${REDIS_MEM_LIMIT:-1g}
        reservations:
          memory: \${REDIS_MEM_RESERVATION:-512m}
    logging:
      driver: "json-file"
      options:
        max-file: "3"
        max-size: "10m"

networks:
  ai-backend-network:
    driver: bridge
EOF
}

generate_litellm_compose() {
    cat > "${DOCKER_DIR}/docker-compose.litellm.yml" << EOF
version: '3.8'

services:
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: ai-platform-litellm
    restart: unless-stopped
    networks:
      - ai-platform-network
      - ai-backend-network
    ports:
      - "127.0.0.1:\${LITELLM_PORT:-4000}:4000"
    environment:
      DATABASE_URL: postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@postgres:5432/\${POSTGRES_DB}
      REDIS_URL: redis://:\${REDIS_PASSWORD}@redis:6379
      LITELLM_MASTER_KEY: \${LITELLM_MASTER_KEY}
      LITELLM_SALT_KEY: \${LITELLM_SALT_KEY}
    volumes:
      - ${CONFIG_DIR}/litellm:/app/config
      - ${LOGS_DIR}/litellm:/app/logs
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 5
    depends_on:
      - postgres
      - redis
    deploy:
      resources:
        limits:
          memory: \${LITELLM_MEM_LIMIT:-2g}
        reservations:
          memory: \${LITELLM_MEM_RESERVATION:-1g}
    logging:
      driver: "json-file"
      options:
        max-file: "3"
        max-size: "10m"

networks:
  ai-platform-network:
    driver: bridge
  ai-backend-network:
    driver: bridge
EOF
}
            }
        else
            log_info "Network already exists: $network"
        fi
    done
    
    log_success "Networks created"
    return 0
}

create_volumes() {
    log_info "Creating Docker volumes..."
    
    local volumes=(
        "ollama_data"
        "open_webui_data"
        "n8n_data"
        "postgres_data"
        "qdrant_data"
    )
    
    for volume in "${volumes[@]}"; do
        if ! docker volume inspect "$volume" &> /dev/null; then
            log_info "Creating volume: $volume"
            docker volume create "$volume" || {
                log_error "Failed to create volume: $volume"
                return 1
            }
        else
            log_info "Volume already exists: $volume"
        fi
    done
    
    log_success "Volumes created"
    return 0
}

pull_images() {
    log_info "Pulling Docker images..."
    
    local compose_cmd
    if command -v docker-compose &> /dev/null; then
        compose_cmd="docker-compose"
    else
        compose_cmd="docker compose"
    fi
    
    if [[ -n "$SPECIFIC_SERVICE" ]]; then
        $compose_cmd -f "$DOCKER_COMPOSE_FILE" pull "$SPECIFIC_SERVICE" || {
            log_error "Failed to pull image for service: $SPECIFIC_SERVICE"
            return 1
        }
    else
        $compose_cmd -f "$DOCKER_COMPOSE_FILE" pull || {
            log_error "Failed to pull images"
            return 1
        }
    fi
    
    log_success "Images pulled"
    return 0
}

build_services() {
    if [[ "$SKIP_BUILD" == "true" ]]; then
        log_info "Skipping build step"
        return 0
    fi
    
    log_info "Building services..."
    
    local compose_cmd
    if command -v docker-compose &> /dev/null; then
        compose_cmd="docker-compose"
    else
        compose_cmd="docker compose"
    fi
    
    if [[ -n "$SPECIFIC_SERVICE" ]]; then
        $compose_cmd -f "$DOCKER_COMPOSE_FILE" build "$SPECIFIC_SERVICE" || {
            log_error "Failed to build service: $SPECIFIC_SERVICE"
            return 1
        }
    else
        $compose_cmd -f "$DOCKER_COMPOSE_FILE" build || {
            log_error "Failed to build services"
            return 1
        }
    fi
    
    log_success "Services built"
    return 0
}

deploy_services() {
    log_info "Deploying services..."
    
    local compose_cmd
    if command -v docker-compose &> /dev/null; then
        compose_cmd="docker-compose"
    else
        compose_cmd="docker compose"
    fi
    
    if [[ -n "$SPECIFIC_SERVICE" ]]; then
        $compose_cmd -f "$DOCKER_COMPOSE_FILE" up -d "$SPECIFIC_SERVICE" || {
            log_error "Failed to deploy service: $SPECIFIC_SERVICE"
            return 1
        }
    else
        $compose_cmd -f "$DOCKER_COMPOSE_FILE" up -d || {
            log_error "Failed to deploy services"
            return 1
        }
    fi
    
    log_success "Services deployed"
    return 0
}

#############################################
# Health Check Functions
#############################################

check_service_health() {
    local service_name=$1
    local port=$2
    local endpoint=${3:-"/"}
    
    log_info "Checking health of $service_name..."
    
    local retries=0
    while [[ $retries -lt $HEALTH_CHECK_RETRIES ]]; do
        if curl -sf "http://localhost:${port}${endpoint}" > /dev/null 2>&1; then
            log_success "$service_name is healthy"
            return 0
        fi
        
        retries=$((retries + 1))
        if [[ $retries -lt $HEALTH_CHECK_RETRIES ]]; then
            log_info "Waiting for $service_name... (attempt $retries/$HEALTH_CHECK_RETRIES)"
            sleep $HEALTH_CHECK_INTERVAL
        fi
    done
    
    log_error "$service_name failed health check"
    return 1
}

verify_deployment() {
    log_info "Verifying deployment..."
    
    local services_to_check=(
        "ollama:11434"
        "open-webui:8080"
        "n8n:5678"
        "postgres:5432"
        "qdrant:6333"
    )
    
    local failed_services=()
    
    for service_info in "${services_to_check[@]}"; do
        IFS=':' read -r service port <<< "$service_info"
        
        # Skip if specific service requested and this isn't it
        if [[ -n "$SPECIFIC_SERVICE" && "$service" != "$SPECIFIC_SERVICE" ]]; then
            continue
        fi
        
        # Check if container is running
        if ! docker ps --filter "name=${service}" --filter "status=running" | grep -q "$service"; then
            log_error "Container $service is not running"
            failed_services+=("$service")
            continue
        fi
        
        # Health check based on service type
        case $service in
            ollama)
                check_service_health "$service" "$port" "/api/tags" || failed_services+=("$service")
                ;;
            open-webui)
                check_service_health "$service" "$port" "/" || failed_services+=("$service")
                ;;
            n8n)
                check_service_health "$service" "$port" "/healthz" || failed_services+=("$service")
                ;;
            qdrant)
                check_service_health "$service" "$port" "/health" || failed_services+=("$service")
                ;;
            postgres)
                if docker exec postgres pg_isready -U "$POSTGRES_USER" > /dev/null 2>&1; then
                    log_success "$service is healthy"
                else
                    log_error "$service failed health check"
                    failed_services+=("$service")
                fi
                ;;
        esac
    done
    
    if [[ ${#failed_services[@]} -eq 0 ]]; then
        log_success "All services are healthy"
        return 0
    else
        log_error "Failed services: ${failed_services[*]}"
        return 1
    fi
}

#############################################
# Display Functions
#############################################

display_service_info() {
    log_info "Deployed Services:"
    echo ""
    echo "  Ollama API:      http://localhost:11434"
    echo "  Open WebUI:      http://localhost:8080"
    echo "  n8n:             http://localhost:5678"
    echo "  Qdrant:          http://localhost:6333"
    echo "  PostgreSQL:      localhost:5432"
    echo ""
    log_info "Use 'docker-compose logs -f [service]' to view logs"
    log_info "Use 'docker-compose ps' to check service status"
}

#############################################
# Argument Parsing
#############################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-build)
                SKIP_BUILD=true
                shift
                ;;
            --service)
                SPECIFIC_SERVICE="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --skip-build       Skip building services"
                echo "  --service SERVICE  Deploy only specific service"
                echo "  -h, --help        Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
    log_step "Starting AI Platform Deployment (Script 2)..."
    log_info "Script Version: 2.0 - Modular Architecture"
    log_info "Execution Time: $(date)"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Validate prerequisites and service selection
    validate_prerequisites || exit 1
    validate_service_selection || exit 1
    
    # Generate modular compose files
    generate_modular_composes || exit 1
    
    # Validate generated compose files
    validate_compose_files || exit 1
    
    # Create Docker networks
    create_networks || exit 1
    
    # Deploy services
    if [ "$SKIP_BUILD" = false ]; then
        log_step "Building and starting services..."
        for compose_file in "${DOCKER_DIR}"/docker-compose.*.yml; do
            if [ -f "$compose_file" ]; then
                service_name=$(basename "$compose_file" | sed 's/docker-compose\.//; s/\.yml//')
                log_info "Deploying $service_name..."
                docker compose -f "$compose_file" up -d --build || {
                    log_error "Failed to deploy $service_name"
                    return 1
                }
                log_success "$service_name deployed"
            fi
        done
    else
        log_step "Starting existing services..."
        for compose_file in "${DOCKER_DIR}"/docker-compose.*.yml; do
            if [ -f "$compose_file" ]; then
                service_name=$(basename "$compose_file" | sed 's/docker-compose\.//; s/\.yml//')
                log_info "Starting $service_name..."
                docker compose -f "$compose_file" up -d || {
                    log_error "Failed to start $service_name"
                    return 1
                }
                log_success "$service_name started"
            fi
        done
    fi
    
    # Wait for services to stabilize
    log_step "Waiting for services to stabilize..."
    sleep 30
    
    # Health check
    perform_health_checks || exit 1
    
    log_success "All services deployed successfully!"
    log_info "Service logs available in: ${LOGS_DIR}"
    log_info "Manage services with: docker compose -f ${DOCKER_DIR}/docker-compose.<service>.yml [up|down|restart|logs]"
}

# Execute main function
main "$@"
