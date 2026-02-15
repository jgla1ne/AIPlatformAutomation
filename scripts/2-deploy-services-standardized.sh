#!/bin/bash

# AI Platform Automation - Script 2 (Standardized Version)
# Version 1.0.0 - Infrastructure Standardization Phase 1

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_ROOT="${DATA_ROOT:-/mnt/data}"
COMPOSE_DIR="${DATA_ROOT}/compose"
LOG_FILE="${DATA_ROOT}/logs/deployment.log"
ENV_FILE="${DATA_ROOT}/.env"

# Service dependencies
declare -A SERVICE_DEPENDENCIES=(
    ["postgres"]=""
    ["redis"]=""
    ["ollama"]=""
    ["litellm"]="postgres redis"
    ["dify"]="postgres redis litellm"
    ["n8n"]="postgres redis"
    ["flowise"]="postgres redis litellm"
    ["anythingllm"]="postgres redis litellm"
    ["openwebui"]="postgres redis litellm"
    ["minio"]=""
    ["tailscale"]=""
    ["grafana"]=""
    ["prometheus"]=""
    ["signal-api"]=""
    ["openclaw"]=""
)

# Service health check endpoints and timeouts
declare -A SERVICE_HEALTH=(
    ["postgres"]="postgresql://ds-admin:FeI4OoQ9sADXETT4UxJ72RTh@postgres:5432/aiplatform"
    ["redis"]="redis://redis:6379"
    ["ollama"]="http://localhost:11434"
    ["litellm"]="http://localhost:4000/health"
    ["dify"]="http://localhost:8080"
    ["n8n"]="http://localhost:5678/healthz"
    ["flowise"]="http://localhost:3000"
    ["anythingllm"]="http://localhost:3001"
    ["openwebui"]="http://localhost:3000"
    ["minio"]="http://localhost:9000/minio/health/live"
    ["tailscale"]="http://localhost:41641"
    ["grafana"]="http://localhost:3001/api/health"
    ["prometheus"]="http://localhost:9090/-/healthy"
    ["signal-api"]="http://localhost:8080"
    ["openclaw"]="http://localhost:18789"
)

# Service health check timeouts
declare -A SERVICE_TIMEOUTS=(
    ["postgres"]="30"
    ["redis"]="30"
    ["ollama"]="45"
    ["litellm"]="60"
    ["dify"]="120"
    ["n8n"]="60"
    ["flowise"]="60"
    ["anythingllm"]="60"
    ["openwebui"]="60"
    ["minio"]="45"
    ["tailscale"]="60"
    ["grafana"]="45"
    ["prometheus"]="45"
    ["signal-api"]="45"
    ["openclaw"]="60"
)

# Standardized logging function
log_service_event() {
    local service_name="$1"
    local event_type="$2"
    local message="$3"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local level="INFO"
    
    case "$event_type" in
        "DEPLOY_FAIL"|"HEALTH_TIMEOUT") level="ERROR" ;;
        "HEALTH_RETRY") level="WARN" ;;
    esac
    
    local log_entry="[$timestamp] [$level] [$service_name] $message"
    
    # Log to file
    echo "$log_entry" >> "$LOG_FILE"
    
    # Output to console
    case "$level" in
        "ERROR") color="$RED" ;;
        "WARN") color="$YELLOW" ;;
        *) color="$GREEN" ;;
    esac
    echo -e "${CYAN}[$timestamp]${NC} ${color}[$level]${NC}[$service_name]${NC} $message"
}

# Standardized configuration generation
generate_service_config() {
    local service_name="$1"
    local service_type="$2"
    
    log_service_event "$service_name" "CONFIG_START" "Generating configuration"
    
    mkdir -p "$COMPOSE_DIR/$service_name"
    
    case "$service_name" in
        "postgres"|"redis"|"ollama")
            # Infrastructure services - use existing configs
            return 0
            ;;
        *)
            # Generate standardized config for other services
            generate_standardized_compose "$service_name" "$service_type"
            ;;
    esac
    
    log_service_event "$service_name" "CONFIG_SUCCESS" "Configuration generated successfully"
}

# Standardized Docker Compose generation
generate_standardized_compose() {
    local service_name="$1"
    local service_type="$2"
    
    cat > "$COMPOSE_DIR/$service_name/docker-compose.yml" <<EOF
version: '3.8'

services:
  $service_name:
    image: \${${service_name^^}_IMAGE:-${service_name}:latest}
    container_name: $service_name
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    networks:
      - ai_platform
    environment:
      - SERVICE_NAME=$service_name
      - SERVICE_TYPE=$service_type
$(generate_service_env_vars "$service_name")
    volumes:
$(generate_service_volumes "$service_name")
    ports:
$(generate_service_ports "$service_name")
    healthcheck:
$(generate_service_healthcheck "$service_name")

networks:
  ai_platform:
    external: true
EOF
}

# Generate service-specific environment variables
generate_service_env_vars() {
    local service_name="$1"
    local env_vars=""
    
    case "$service_name" in
        "litellm")
            env_vars="      - LITELLM_MASTER_KEY=\${LITELLM_MASTER_KEY}
      - DATABASE_URL=postgresql://\${POSTGRES_USER:-postgres}:\${POSTGRES_PASSWORD}@postgres:5432/\${POSTGRES_DB:-aiplatform}
      - REDIS_URL=redis://redis:6379
      - REDIS_PASSWORD=\${REDIS_PASSWORD}"
            ;;
        "dify")
            env_vars="      - CONSOLE_WEB_URL=http://localhost:8080
      - CONSOLE_API_URL=http://localhost:5001
      - DB_USERNAME=\${POSTGRES_USER:-postgres}
      - DB_PASSWORD=\${POSTGRES_PASSWORD}
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_DATABASE=\${POSTGRES_DB:-aiplatform}
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=\${REDIS_PASSWORD}"
            ;;
        "n8n")
            env_vars="      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=\${N8N_USER:-admin}
      - N8N_BASIC_AUTH_PASSWORD=\${N8N_PASSWORD}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=\${POSTGRES_DB:-aiplatform}
      - DB_POSTGRESDB_USER=\${POSTGRES_USER:-postgres}
      - DB_POSTGRESDB_PASSWORD=\${POSTGRES_PASSWORD}"
            ;;
    esac
    
    echo "$env_vars"
}

# Generate service-specific volumes
generate_service_volumes() {
    local service_name="$1"
    local volumes=""
    
    case "$service_name" in
        "litellm")
            volumes="      - ${DATA_ROOT}/litellm:/app/data
      - ${DATA_ROOT}/litellm/config.yaml:/app/config.yaml"
            ;;
        "dify")
            volumes="      - ${DATA_ROOT}/dify:/app/storage"
            ;;
        "n8n")
            volumes="      - ${DATA_ROOT}/n8n:/home/node/.n8n"
            ;;
        *)
            volumes="      - ${DATA_ROOT}/${service_name}:/data"
            ;;
    esac
    
    echo "$volumes"
}

# Generate service-specific ports
generate_service_ports() {
    local service_name="$1"
    local ports=""
    
    case "$service_name" in
        "litellm")
            ports="      - \"4000:4000\""
            ;;
        "dify")
            ports="      - \"8080:3000\"
      - \"5001:5001\""
            ;;
        "n8n")
            ports="      - \"5678:5678\""
            ;;
        *)
            ports="      - \"\${${service_name^^}_PORT:-3000}:3000\""
            ;;
    esac
    
    echo "$ports"
}

# Generate service-specific health checks
generate_service_healthcheck() {
    local service_name="$1"
    local healthcheck=""
    
    case "$service_name" in
        "postgres")
            healthcheck="      test: [\"CMD-SHELL\", \"pg_isready -U \${POSTGRES_USER:-postgres} -d \${POSTGRES_DB:-aiplatform}\"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s"
            ;;
        "redis")
            healthcheck="      test: [\"CMD\", \"redis-cli\", \"ping\"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s"
            ;;
        "litellm")
            healthcheck="      test: [\"CMD\", \"curl\", \"-f\", \"http://localhost:4000/health\"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s"
            ;;
        "dify")
            healthcheck="      test: [\"CMD\", \"curl\", \"-f\", \"http://localhost:3000\"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 120s"
            ;;
        *)
            healthcheck="      test: [\"CMD\", \"curl\", \"-f\", \"http://localhost:3000\"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s"
            ;;
    esac
    
    echo "$healthcheck"
}

# Standardized health checking with exponential backoff
wait_for_service_healthy() {
    local service_name="$1"
    local service_type="$2"
    local max_attempts="${SERVICE_TIMEOUTS[$service_name]:-60}"
    local base_delay=5
    
    log_service_event "$service_name" "HEALTH_START" "Starting health checks (max: $max_attempts attempts)"
    
    for ((attempt=1; attempt<=max_attempts; attempt++)); do
        # Exponential backoff
        local delay=$((base_delay + (attempt - 1) * 2))
        sleep "$delay"
        
        if check_service_health "$service_name"; then
            log_service_event "$service_name" "HEALTH_SUCCESS" "Healthy after $attempt attempts"
            return 0
        else
            log_service_event "$service_name" "HEALTH_RETRY" "Attempt $attempt/$max_attempts failed, retrying in ${delay}s"
        fi
    done
    
    log_service_event "$service_name" "HEALTH_TIMEOUT" "Failed after $max_attempts attempts"
    return 1
}

# Check service health
check_service_health() {
    local service_name="$1"
    local health_url="${SERVICE_HEALTH[$service_name]}"
    
    case "$service_name" in
        "postgres")
            docker exec postgres pg_isready -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-aiplatform}" >/dev/null 2>&1
            ;;
        "redis")
            docker exec redis redis-cli ping >/dev/null 2>&1
            ;;
        *)
            curl -f -s --max-time 10 "$health_url" >/dev/null 2>&1
            ;;
    esac
}

# Wait for dependencies
wait_for_dependencies() {
    local service_name="$1"
    local dependencies="${SERVICE_DEPENDENCIES[$service_name]}"
    
    if [[ -z "$dependencies" ]]; then
        return 0
    fi
    
    log_service_event "$service_name" "DEPS_WAIT" "Waiting for dependencies: $dependencies"
    
    for dep in $dependencies; do
        wait_for_service_healthy "$dep" "infrastructure"
    done
    
    log_service_event "$service_name" "DEPS_READY" "All dependencies ready"
}

# Standardized deployment function
deploy_service_unified() {
    local service_name="$1"
    local service_type="$2"
    
    log_service_event "$service_name" "DEPLOY_START" "Starting deployment"
    
    # Wait for dependencies
    wait_for_dependencies "$service_name"
    
    # Generate configuration
    generate_service_config "$service_name" "$service_type"
    
    # Deploy with Docker Compose
    log_service_event "$service_name" "DEPLOY_COMPOSE" "Starting container"
    if docker-compose -f "$COMPOSE_DIR/$service_name/docker-compose.yml" up -d >> "$LOG_FILE" 2>&1; then
        log_service_event "$service_name" "DEPLOY_SUCCESS" "Container started successfully"
    else
        log_service_event "$service_name" "DEPLOY_FAIL" "Failed to start container"
        return 1
    fi
    
    # Wait for health
    if wait_for_service_healthy "$service_name" "$service_type"; then
        log_service_event "$service_name" "DEPLOY_COMPLETE" "Deployment completed successfully"
        return 0
    else
        log_service_event "$service_name" "DEPLOY_FAIL" "Deployment failed - health check timeout"
        return 1
    fi
}

# Main deployment function
deploy_services() {
    local service_type="$1"
    shift
    local services=("$@")
    
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  🚀 ${BOLD}DEPLOYING $service_type SERVICES${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    local deployed=0
    local total=${#services[@]}
    
    for service in "${services[@]}"; do
        if service_exists "$service"; then
            echo -e "${CYAN}  [${deployed}/${total}]${NC} Deploying ${BOLD}$service${NC}..."
            
            if deploy_service_unified "$service" "$service_type"; then
                ((deployed++))
                echo -e "  ✅ ${GREEN}$service${NC} deployed successfully"
            else
                echo -e "  ❌ ${RED}$service${NC} deployment failed"
            fi
        fi
    done
    
    echo -e "\n${CYAN}$service_type deployment completed: $deployed/$total services${NC}\n"
}

# Check if service exists in configuration
service_exists() {
    local service="$1"
    # Check if service is enabled in .env file
    grep -q "^${service^^}_ENABLED=true" "$ENV_FILE" 2>/dev/null || \
    grep -q "^SERVICES=.*$service" "$ENV_FILE" 2>/dev/null
}

# Main execution
main() {
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║            AI PLATFORM AUTOMATION - DEPLOYMENT                 ║${NC}"
    echo -e "${CYAN}║              Standardized Version 1.0.0                      ║${NC}"
    echo -e "${CYAN}║           Unified Services Deployment                       ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Load environment
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
        log_service_event "SYSTEM" "ENV_LOADED" "Environment loaded successfully"
    else
        echo -e "${RED}Error: Environment file not found at $ENV_FILE${NC}"
        exit 1
    fi
    
    # Create network if not exists
    if ! docker network inspect ai_platform >/dev/null 2>&1; then
        docker network create ai_platform
        log_service_event "SYSTEM" "NETWORK_CREATE" "Created ai_platform network"
    fi
    
    # Deploy services by type
    # Infrastructure services
    deploy_services "INFRASTRUCTURE" postgres redis ollama
    
    # LLM services (skip LiteLLM for now due to hardcoded Azure config)
    # deploy_services "LLM" litellm
    
    # AI Application services
    deploy_services "AI_APPLICATIONS" dify n8n flowise anythingllm openwebui
    
    # Workflow and monitoring services
    deploy_services "WORKFLOW" signal-api openclaw
    deploy_services "MONITORING" grafana prometheus
    
    # Storage services
    deploy_services "STORAGE" minio
    
    # Network services
    deploy_services "NETWORK" tailscale
    
    echo -e "\n${GREEN}🎉 Deployment completed!${NC}"
    echo -e "${CYAN}Check service status: docker ps${NC}"
    echo -e "${CYAN}View logs: tail -f $LOG_FILE${NC}"
}

# Run main function
main "$@"
