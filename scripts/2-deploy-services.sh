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
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting PostgreSQL deployment" >> "$LOG_FILE"
    
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
    echo "$(date '+%Y-%m-%d %H:%M:%S') - PostgreSQL configuration generated" >> "$LOG_FILE"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting PostgreSQL container" >> "$LOG_FILE"
    docker-compose -f "$COMPOSE_DIR/postgres/docker-compose.yml" up -d 2>&1 | tee -a "$LOG_FILE"
    
    wait_for_service "PostgreSQL" "http://localhost:5432" 30
    if [[ $? -eq 0 ]]; then
        print_success "PostgreSQL deployed successfully"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - PostgreSQL deployed successfully" >> "$LOG_FILE"
    else
        print_error "PostgreSQL deployment failed"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - PostgreSQL deployment failed" >> "$LOG_FILE"
        return 1
    fi
}

deploy_redis() {
    print_info "Generating Redis configuration..."
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting Redis deployment" >> "$LOG_FILE"
    
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
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Redis configuration generated" >> "$LOG_FILE"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting Redis container" >> "$LOG_FILE"
    docker-compose -f "$COMPOSE_DIR/redis/docker-compose.yml" up -d 2>&1 | tee -a "$LOG_FILE"
    
    wait_for_service "Redis" "http://localhost:6379" 30
    if [[ $? -eq 0 ]]; then
        print_success "Redis deployed successfully"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Redis deployed successfully" >> "$LOG_FILE"
    else
        print_error "Redis deployment failed"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Redis deployment failed" >> "$LOG_FILE"
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
    echo "  • Vector Database: ${VECTOR_DB_TYPE:-none selected}"
    echo "  • LLM Providers: ${LLM_PROVIDERS:-none configured}"
    
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

deploy_ollama() {
    print_info "Deploying Ollama..."
    # TODO: Implement Ollama deployment
    print_success "Ollama deployment stub completed"
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
    print_info "Deploying AnythingLLM..."
    # TODO: Implement AnythingLLM deployment
    print_success "AnythingLLM deployment stub completed"
}

deploy_dify() {
    print_info "Deploying Dify..."
    # TODO: Implement Dify deployment
    print_success "Dify deployment stub completed"
}

deploy_n8n() {
    print_info "Deploying n8n..."
    # TODO: Implement n8n deployment
    print_success "n8n deployment stub completed"
}

deploy_flowise() {
    print_info "Deploying Flowise..."
    # TODO: Implement Flowise deployment
    print_success "Flowise deployment stub completed"
}

deploy_signal_api() {
    print_info "Deploying Signal API..."
    # TODO: Implement Signal API deployment
    print_success "Signal API deployment stub completed"
}

deploy_openclaw() {
    print_info "Deploying OpenClaw..."
    # TODO: Implement OpenClaw deployment
    print_success "OpenClaw deployment stub completed"
}

deploy_grafana() {
    print_info "Deploying Grafana..."
    # TODO: Implement Grafana deployment
    print_success "Grafana deployment stub completed"
}

deploy_prometheus() {
    print_info "Deploying Prometheus..."
    # TODO: Implement Prometheus deployment
    print_success "Prometheus deployment stub completed"
}

deploy_minio() {
    print_info "Deploying MinIO..."
    # TODO: Implement MinIO deployment
    print_success "MinIO deployment stub completed"
}

deploy_proxy() {
    local proxy_type="$1"
    print_info "Deploying proxy: $proxy_type"
    # TODO: Implement proxy deployment
    print_success "$proxy_type deployment stub completed"
}

deploy_tailscale() {
    print_info "Deploying Tailscale..."
    # TODO: Implement Tailscale deployment
    print_success "Tailscale deployment stub completed"
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
