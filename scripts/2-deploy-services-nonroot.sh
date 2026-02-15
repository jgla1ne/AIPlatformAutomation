#!/bin/bash

#==============================================================================
# Script 2: Unified Services Deployment (Non-Root Version)
# Purpose: Deploy all selected services using non-root Docker containers
# Version: 6.0.0 - Non-Root Docker Deployment
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

# 🔥 CRITICAL: User Detection for Non-Root Deployment (preserve original user even with sudo)
if [[ -n "${SUDO_USER:-}" ]]; then
    readonly DETECTED_UID=$(id -u "$SUDO_USER")
    readonly DETECTED_GID=$(id -g "$SUDO_USER")
    readonly DETECTED_USER="$SUDO_USER"
else
    readonly DETECTED_UID=$(id -u)
    readonly DETECTED_GID=$(id -g)
    readonly DETECTED_USER=$(id -un)
fi

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

# Print functions
print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 🔥 NEW: User Detection Display
show_user_info() {
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  👤 ${BOLD}NON-ROOT DEPLOYMENT MODE${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  🆔 Detected User: ${GREEN}$DETECTED_USER${NC}"
    echo -e "  🔢 UID: ${GREEN}$DETECTED_UID${NC}"
    echo -e "  🔢 GID: ${GREEN}$DETECTED_GID${NC}"
    echo -e "  🐳 All containers will run as non-root user"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Source environment (handle readonly variables)
if [[ -f "$ENV_FILE" ]]; then
    # Export all variables except readonly ones defined in this script
    while IFS= read -r line; do
        if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            var_name="${line%%=*}"
            # Skip readonly variables defined in this script
            case "$var_name" in
                DATA_ROOT|METADATA_DIR|STATE_FILE|LOG_FILE|ENV_FILE|SERVICES_FILE|COMPOSE_DIR|CONFIG_DIR|CREDENTIALS_FILE|DETECTED_UID|DETECTED_GID|DETECTED_USER)
                    continue
                    ;;
                *)
                    export "$line"
                    ;;
            esac
        fi
    done < "$ENV_FILE"
else
    print_error "Environment file not found. Run script 1 first."
    exit 1
fi

# Create directories with proper ownership
create_directories() {
    print_info "Creating directories with proper ownership..."
    
    # Create all necessary directories
    mkdir -p "$COMPOSE_DIR" "$CONFIG_DIR" "$METADATA_DIR" "$(dirname "$LOG_FILE")"
    
    # Set ownership to detected user
    chown -R "$DETECTED_UID:$DETECTED_GID" "$DATA_ROOT"
    
    print_success "Directories created and ownership set to $DETECTED_USER ($DETECTED_UID:$DETECTED_GID)"
}

# 🔥 NEW: Generate Docker Compose with User Mapping
generate_compose_with_user() {
    local service_name="$1"
    local service_dir="$COMPOSE_DIR/$service_name"
    
    mkdir -p "$service_dir"
    
    cat > "$service_dir/docker-compose.yml" <<EOF
version: '3.8'

services:
  $service_name:
    image: \${${service_name^^}_IMAGE:-${service_name}:latest}
    container_name: $service_name
    restart: unless-stopped
    # 🔥 CRITICAL: Non-root user mapping
    user: "$DETECTED_UID:$DETECTED_GID"
    networks:
      - ai_platform
    environment:
      - SERVICE_NAME=$service_name
      - PUID=$DETECTED_UID
      - PGID=$DETECTED_GID
      - TZ=\${TIMEZONE:-UTC}
$(generate_service_env "$service_name")
    volumes:
$(generate_service_volumes "$service_name")
    ports:
$(generate_service_ports "$service_name")
    healthcheck:
$(generate_healthcheck "$service_name")

networks:
  ai_platform:
    external: true
EOF

    print_success "$service_name Docker Compose generated with user mapping"
}

# 🔥 UPDATED: Ollama Deployment (Non-Root)
deploy_ollama() {
    print_info "Deploying Ollama with non-root user mapping..."
    
    generate_compose_with_user "ollama"
    
    # Create Ollama data directory with proper ownership
    mkdir -p "$DATA_ROOT/ollama"
    chown -R "$DETECTED_UID:$DETECTED_GID" "$DATA_ROOT/ollama"
    
    # Deploy using docker-compose (NOT docker run)
    cd "$COMPOSE_DIR/ollama"
    docker-compose up -d
    
    # Wait for Ollama to be ready
    wait_for_service "Ollama" "http://localhost:${OLLAMA_PORT:-11434}" 45
    
    if [[ $? -eq 0 ]]; then
        print_success "Ollama deployed successfully as non-root user"
        return 0
    else
        print_error "Ollama deployment failed"
        return 1
    fi
}

# 🔥 UPDATED: Generate Service Environment Variables
generate_service_env() {
    local service_name="$1"
    local env_vars=""
    
    case "$service_name" in
        "postgres")
            env_vars="      - POSTGRES_USER=\${POSTGRES_USER:-postgres}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_DB=\${POSTGRES_DB:-aiplatform}
      - PGDATA=/var/lib/postgresql/data/pgdata
      - TZ=\${TIMEZONE:-UTC}"
            ;;
        "redis")
            env_vars="      - REDIS_PASSWORD=\${REDIS_PASSWORD}
      - TZ=\${TIMEZONE:-UTC}"
            ;;
        "ollama")
            env_vars="      - OLLAMA_HOST=0.0.0.0
      - TZ=\${TIMEZONE:-UTC}"
            ;;
        "litellm")
            env_vars="      - LITELLM_MASTER_KEY=\${LITELLM_MASTER_KEY}
      - DATABASE_URL=postgresql://\${POSTGRES_USER:-postgres}:\${POSTGRES_PASSWORD}@postgres:5432/\${POSTGRES_DB:-aiplatform}
      - REDIS_URL=redis://redis:6379
      - REDIS_PASSWORD=\${REDIS_PASSWORD}
      - TZ=\${TIMEZONE:-UTC}"
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
      - REDIS_PASSWORD=\${REDIS_PASSWORD}
      - TZ=\${TIMEZONE:-UTC}"
            ;;
        *)
            env_vars="      - TZ=\${TIMEZONE:-UTC}"
            ;;
    esac
    
    echo "$env_vars"
}

# 🔥 UPDATED: Generate Service Volumes with User Ownership
generate_service_volumes() {
    local service_name="$1"
    local volumes=""
    
    case "$service_name" in
        "postgres")
            volumes="      - ${DATA_ROOT}/postgres:/var/lib/postgresql/data
      - ${DATA_ROOT}/logs/postgres:/var/log/postgresql"
            ;;
        "redis")
            volumes="      - ${DATA_ROOT}/redis:/data
      - ${DATA_ROOT}/logs/redis:/var/log/redis"
            ;;
        "ollama")
            volumes="      - ${DATA_ROOT}/ollama:/root/.ollama"
            ;;
        "litellm")
            volumes="      - ${DATA_ROOT}/litellm:/app/data
      - ${DATA_ROOT}/litellm/config.yaml:/app/config.yaml"
            ;;
        "dify")
            volumes="      - ${DATA_ROOT}/dify:/app/storage
      - ${DATA_ROOT}/logs/dify:/app/logs"
            ;;
        *)
            volumes="      - ${DATA_ROOT}/${service_name}:/data"
            ;;
    esac
    
    echo "$volumes"
}

# 🔥 UPDATED: Generate Service Ports
generate_service_ports() {
    local service_name="$1"
    local ports=""
    
    case "$service_name" in
        "postgres")
            ports="      - \"127.0.0.1:5432:5432\""
            ;;
        "redis")
            ports="      - \"127.0.0.1:6379:6379\""
            ;;
        "ollama")
            ports="      - \"${OLLAMA_PORT:-11434}:11434\""
            ;;
        "litellm")
            ports="      - \"4000:4000\""
            ;;
        "dify")
            ports="      - \"8080:3000\"
      - \"5001:5001\""
            ;;
        *)
            ports="      - \"3000:3000\""
            ;;
    esac
    
    echo "$ports"
}

# 🔥 UPDATED: Generate Health Checks
generate_healthcheck() {
    local service_name="$1"
    local healthcheck=""
    
    case "$service_name" in
        "postgres")
            healthcheck="      test: [\"CMD-SHELL\", \"pg_isready -U \${POSTGRES_USER:-postgres} -d \${POSTGRES_DB:-aiplatform}\"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s"
            ;;
        "redis")
            healthcheck="      test: [\"CMD\", \"redis-cli\", \"ping\"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s"
            ;;
        "ollama")
            healthcheck="      test: [\"CMD\", \"curl\", \"-f\", \"http://localhost:11434\"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 45s"
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

# Wait for service health
wait_for_service() {
    local service_name="$1"
    local health_url="$2"
    local max_attempts="$3"
    local attempt=0
    
    print_info "Waiting for $service_name to be healthy..."
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -f -s --max-time 10 "$health_url" >/dev/null 2>&1; then
            print_success "$service_name is healthy"
            return 0
        fi
        
        attempt=$((attempt + 1))
        sleep 5
    done
    
    print_error "$service_name health check failed after $max_attempts attempts"
    return 1
}

# 🔥 UPDATED: Deploy Service (Non-Root)
deploy_service() {
    local service_name="$1"
    
    print_info "Deploying $service_name as non-root user ($DETECTED_USER)..."
    
    # Generate compose file with user mapping
    generate_compose_with_user "$service_name"
    
    # Create data directory with proper ownership
    mkdir -p "$DATA_ROOT/$service_name"
    chown -R "$DETECTED_UID:$DETECTED_GID" "$DATA_ROOT/$service_name"
    
    # Deploy using docker-compose
    cd "$COMPOSE_DIR/$service_name"
    docker-compose up -d
    
    # Wait for service to be healthy
    local health_url=""
    local timeout=60
    
    case "$service_name" in
        "postgres")
            health_url="tcp://127.0.0.1:5432"
            timeout=30
            ;;
        "redis")
            health_url="tcp://127.0.0.1:6379"
            timeout=30
            ;;
        "ollama")
            health_url="http://localhost:${OLLAMA_PORT:-11434}"
            timeout=45
            ;;
        "litellm")
            health_url="http://localhost:4000"
            timeout=60
            ;;
        "dify")
            health_url="http://localhost:8080"
            timeout=120
            ;;
        *)
            health_url="http://localhost:3000"
            timeout=60
            ;;
    esac
    
    wait_for_service "$service_name" "$health_url" "$timeout"
    
    if [[ $? -eq 0 ]]; then
        print_success "$service_name deployed successfully as non-root user"
        return 0
    else
        print_error "$service_name deployment failed"
        return 1
    fi
}

# Main deployment function
main() {
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║            AI PLATFORM AUTOMATION - DEPLOYMENT                 ║${NC}"
    echo -e "${CYAN}║              Non-Root Version 6.0.0                      ║${NC}"
    echo -e "${CYAN}║           User: $DETECTED_USER ($DETECTED_UID:$DETECTED_GID)        ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Show user information
    show_user_info
    
    # Create directories with proper ownership
    create_directories
    
    # Create network if not exists
    if ! docker network inspect ai_platform >/dev/null 2>&1; then
        docker network create ai_platform
        print_success "Created ai_platform network"
    fi
    
    # Deploy infrastructure services
    print_info "Deploying infrastructure services..."
    
    # Deploy in order of dependency
    local services=("postgres" "redis" "ollama")
    
    for service in "${services[@]}"; do
        if deploy_service "$service"; then
            print_success "$service deployment completed"
        else
            print_error "$service deployment failed"
        fi
    done
    
    echo -e "\n${GREEN}🎉 Non-Root deployment completed!${NC}"
    echo -e "${CYAN}All containers are running as user: $DETECTED_USER ($DETECTED_UID:$DETECTED_GID)${NC}"
    echo -e "${CYAN}Check container status: docker ps --format 'table {{.Names}}\t{{.User}}\t{{.Status}}'${NC}"
}

# Run main function
main "$@"
