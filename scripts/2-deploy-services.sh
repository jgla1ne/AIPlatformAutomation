#!/bin/bash

#==============================================================================
# Script 2: Non-Root Docker Deployment with AppArmor Security
# Purpose: Deploy all selected services using Script 1 configuration
# Version: 7.0.0 - AppArmor Security & Complete Service Coverage
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

# 🔥 NEW: AppArmor Security Configuration
readonly APPARMOR_PROFILES_DIR="$DATA_ROOT/security/apparmor"
readonly SECURITY_COMPLIANCE=true

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

# 🔥 NEW: AppArmor Security Functions
setup_apparmor_security() {
    print_info "Setting up AppArmor security profiles..."
    
    # Create AppArmor profiles directory
    mkdir -p "$APPARMOR_PROFILES_DIR"
    
    # Check if AppArmor is available
    if ! command -v aa-status >/dev/null 2>&1; then
        print_warning "AppArmor not available, installing..."
        apt-get update && apt-get install -y apparmor apparmor-utils
    fi
    
    # Enable AppArmor if not already enabled
    if ! aa-status --enabled >/dev/null 2>&1; then
        print_warning "Enabling AppArmor..."
        systemctl enable apparmor
        systemctl start apparmor
    fi
    
    print_success "AppArmor security configured"
}

# 🔥 NEW: Generate AppArmor Profile for Service
generate_apparmor_profile() {
    local service_name="$1"
    local profile_file="$APPARMOR_PROFILES_DIR/${service_name}.profile"
    
    cat > "$profile_file" <<EOF
#include <tunables/global>

profile ${service_name} flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  #include <abstractions/nameservice>
  
  # Network access
  network inet tcp,
  network inet udp,
  
  # File system access (restricted)
  /mnt/data/${service_name}/** rw,
  /tmp/** rw,
  /var/log/** w,
  
  # Deny sensitive system files
  deny /etc/shadow r,
  deny /etc/passwd r,
  deny /etc/ssh/** r,
  deny /root/** rw,
  deny /home/** rw,
  
  # Docker-specific restrictions
  deny /var/lib/docker/** rw,
  deny /sys/** rw,
  deny /proc/** rw,
  
  # Allow necessary system files
  /etc/hosts r,
  /etc/resolv.conf r,
  /etc/localtime r,
  /usr/share/zoneinfo/** r,
}
EOF
    
    # Load the AppArmor profile
    if aa-status | grep -q "${service_name}"; then
        print_info "AppArmor profile for ${service_name} already loaded"
    else
        apparmor_parser -r "$profile_file" || print_warning "Failed to load AppArmor profile for ${service_name}"
    fi
}

# Source environment (handle readonly variables)
if [[ -f "$ENV_FILE" ]]; then
    # Export all variables except readonly ones defined in this script
    while IFS= read -r line; do
        if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            var_name="${line%%=*}"
            # Skip readonly variables defined in this script
            case "$var_name" in
                DATA_ROOT|METADATA_DIR|STATE_FILE|LOG_FILE|ENV_FILE|SERVICES_FILE|COMPOSE_DIR|CONFIG_DIR|CREDENTIALS_FILE|APPARMOR_PROFILES_DIR|SECURITY_COMPLIANCE)
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

# 🔥 NEW: Load Selected Services from JSON
load_selected_services() {
    if [[ ! -f "$SERVICES_FILE" ]]; then
        print_error "Selected services file not found. Run script 1 first."
        exit 1
    fi
    
    # Parse JSON and extract service keys
    SELECTED_SERVICES=($(jq -r '.services[].key' "$SERVICES_FILE"))
    TOTAL_SERVICES=${#SELECTED_SERVICES[@]}
    
    print_info "Loaded ${TOTAL_SERVICES} selected services from Script 1"
    print_info "Services: ${SELECTED_SERVICES[*]}"
}

# 🔥 UPDATED: Generate Complete Compose Templates with Security
generate_compose_template() {
    local service_name="$1"
    local service_dir="$COMPOSE_DIR/$service_name"
    
    mkdir -p "$service_dir"
    
    # Get user mapping from environment
    local user_mapping="${RUNNING_UID:-1001}:${RUNNING_GID:-1001}"
    
    cat > "$service_dir/docker-compose.yml" <<EOF
version: '3.8'

services:
  $service_name:
$(generate_service_config "$service_name" "$user_mapping")
    networks:
      - ai_platform
$(generate_service_security "$service_name")
    environment:
$(generate_service_env "$service_name")
    volumes:
$(generate_service_volumes "$service_name")
    ports:
$(generate_service_ports "$service_name")
    healthcheck:
$(generate_healthcheck "$service_name")
    restart: unless-stopped

networks:
  ai_platform:
    external: true
EOF

    print_success "$service_name Docker Compose template generated with security"
}

# 🔥 NEW: Generate Service Configuration
generate_service_config() {
    local service_name="$1"
    local user_mapping="$2"
    
    case "$service_name" in
        "postgres")
            echo "    image: postgres:15-alpine
    container_name: postgres
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "redis")
            echo "    image: redis:7-alpine
    container_name: redis
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "ollama")
            echo "    image: ollama/ollama:latest
    container_name: ollama
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "litellm")
            echo "    image: ghcr.io/berriai/litellm:main
    container_name: litellm
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "dify")
            echo "    image: langgenius/dify-web:latest
    container_name: dify-web
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "n8n")
            echo "    image: n8nio/n8n:latest
    container_name: n8n
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "flowise")
            echo "    image: flowiseai/flowise:latest
    container_name: flowise
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "anythingllm")
            echo "    image: mintplexlabs/anythingllm:latest
    container_name: anythingllm
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "openwebui")
            echo "    image: ghcr.io/open-webui/open-webui:main
    container_name: openwebui
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "signal-api")
            echo "    image: ghcr.io/wppconnect-team/wppconnect:latest
    container_name: signal-api
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "openclaw")
            echo "    image: openclaw/openclaw:latest
    container_name: openclaw
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "grafana")
            echo "    image: grafana/grafana:latest
    container_name: grafana
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "prometheus")
            echo "    image: prom/prometheus:latest
    container_name: prometheus
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "minio")
            echo "    image: minio/minio:latest
    container_name: minio
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "tailscale")
            echo "    image: tailscale/tailscale:latest
    container_name: tailscale
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        *)
            echo "    image: ${service_name}:latest
    container_name: $service_name
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
    esac
}

# 🔥 NEW: Generate Security Configuration
generate_service_security() {
    if [[ "$SECURITY_COMPLIANCE" == "true" ]]; then
        echo "    # 🔥 APPARMOR SECURITY
    security_opt:
      - apparmor:$service_name
    # 🔥 DOCKER SECURITY HARDENING
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETGID
      - SETUID
    read_only: true
    tmpfs:
      - /tmp:noexec,nosuid,size=100m"
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
      - PUID=\${RUNNING_UID:-1001}
      - PGID=\${RUNNING_GID:-1001}
      - TZ=\${TIMEZONE:-UTC}"
            ;;
        "redis")
            env_vars="      - REDIS_PASSWORD=\${REDIS_PASSWORD}
      - PUID=\${RUNNING_UID:-1001}
      - PGID=\${RUNNING_GID:-1001}
      - TZ=\${TIMEZONE:-UTC}"
            ;;
        "ollama")
            env_vars="      - OLLAMA_HOST=0.0.0.0
      - PUID=\${RUNNING_UID:-1001}
      - PGID=\${RUNNING_GID:-1001}
      - TZ=\${TIMEZONE:-UTC}"
            ;;
        "litellm")
            env_vars="      - LITELLM_MASTER_KEY=\${LITELLM_MASTER_KEY}
      - DATABASE_URL=postgresql://\${POSTGRES_USER:-postgres}:\${POSTGRES_PASSWORD}@postgres:5432/\${POSTGRES_DB:-aiplatform}
      - REDIS_URL=redis://redis:6379
      - REDIS_PASSWORD=\${REDIS_PASSWORD}
      - PUID=\${RUNNING_UID:-1001}
      - PGID=\${RUNNING_GID:-1001}
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
      - PUID=\${RUNNING_UID:-1001}
      - PGID=\${RUNNING_GID:-1001}
      - TZ=\${TIMEZONE:-UTC}"
            ;;
        *)
            env_vars="      - PUID=\${RUNNING_UID:-1001}
      - PGID=\${RUNNING_GID:-1001}
      - TZ=\${TIMEZONE:-UTC}"
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
            ports="      - \"\${OLLAMA_PORT:-11434}:11434\""
            ;;
        "litellm")
            ports="      - \"4000:4000\""
            ;;
        "dify")
            ports="      - \"8080:3000\"
      - \"5001:5001\""
            ;;
        "n8n")
            ports="      - \"\${N8N_PORT:-5678}:5678\""
            ;;
        "flowise")
            ports="      - \"\${FLOWISE_PORT:-3000}:3000\""
            ;;
        "anythingllm")
            ports="      - \"\${ANYTHINGLLM_PORT:-3001}:3001\""
            ;;
        "openwebui")
            ports="      - \"3000:3000\""
            ;;
        "signal-api")
            ports="      - \"\${SIGNAL_API_PORT:-8080}:8080\""
            ;;
        "openclaw")
            ports="      - \"\${OPENCLAW_PORT:-8081}:8081\""
            ;;
        "grafana")
            ports="      - \"3000:3000\""
            ;;
        "prometheus")
            ports="      - \"9090:9090\""
            ;;
        "minio")
            ports="      - \"9000:9000\"
      - \"9001:9001\""
            ;;
        "tailscale")
            ports="      - \"41641:41641/udp\""
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

# 🔥 UPDATED: Deploy Service with Security
deploy_service() {
    local service_name="$1"
    
    print_info "Deploying $service_name with non-root user mapping and security..."
    
    # Generate compose template with security
    generate_compose_template "$service_name"
    
    # Generate AppArmor profile
    if [[ "$SECURITY_COMPLIANCE" == "true" ]]; then
        generate_apparmor_profile "$service_name"
    fi
    
    # Create data directory with proper ownership
    mkdir -p "$DATA_ROOT/$service_name"
    chown -R "${RUNNING_UID:-1001}:${RUNNING_GID:-1001}" "$DATA_ROOT/$service_name"
    
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
        print_success "$service_name deployed successfully as non-root user with security"
        return 0
    else
        print_error "$service_name deployment failed"
        return 1
    fi
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

# 🔥 NEW: Comprehensive Cleanup Function
cleanup_previous_deployments() {
    print_info "Cleaning up previous deployments..."
    
    # Stop and remove all AI platform containers
    print_info "Stopping AI platform containers..."
    local containers=$(docker ps -q --filter "name=postgres|redis|ollama|litellm|dify|n8n|flowise|anythingllm|openwebui|signal-api|openclaw|grafana|prometheus|minio|tailscale" 2>/dev/null || true)
    
    if [[ -n "$containers" ]]; then
        echo "$containers" | xargs -r docker stop
        echo "$containers" | xargs -r docker rm
        print_success "Stopped and removed previous containers"
    else
        print_info "No previous containers found"
    fi
    
    # Remove orphaned containers
    print_info "Removing orphaned containers..."
    docker container prune -f >/dev/null 2>&1 || true
    
    # Clean up AI platform networks
    print_info "Cleaning up AI platform networks..."
    local networks=$(docker network ls -q --filter "name=ai_platform" 2>/dev/null || true)
    if [[ -n "$networks" ]]; then
        echo "$networks" | xargs -r docker network rm
        print_success "Removed AI platform networks"
    fi
    
    # Clean up AppArmor profiles
    print_info "Cleaning up AppArmor profiles..."
    for service in postgres redis ollama litellm dify n8n flowise anythingllm openwebui signal-api openclaw grafana prometheus minio tailscale; do
        if aa-status | grep -q "$service" 2>/dev/null; then
            aa-complain "$service" 2>/dev/null || true
            apparmor_parser -R "/etc/apparmor.d/$service" 2>/dev/null || true
        fi
    done
    
    # Clean up compose files (but keep templates from Script 1)
    print_info "Cleaning up deployment artifacts..."
    for service in postgres redis ollama litellm dify n8n flowise anythingllm openwebui signal-api openclaw grafana prometheus minio tailscale; do
        if [[ -f "$COMPOSE_DIR/$service/docker-compose.yml" ]]; then
            cd "$COMPOSE_DIR/$service"
            docker-compose down -v 2>/dev/null || true
            cd - >/dev/null
        fi
    done
    
    # Clean up temporary files and logs
    print_info "Cleaning up temporary files..."
    rm -f "$DATA_ROOT/logs/deployment.log" 2>/dev/null || true
    rm -f "$DATA_ROOT/.deployment_lock" 2>/dev/null || true
    
    # Ensure no background processes are running
    print_info "Terminating any background deployment processes..."
    pkill -f "2-deploy-services.sh" 2>/dev/null || true
    pkill -f "docker-compose" 2>/dev/null || true
    
    print_success "Pre-deployment cleanup completed"
}

# Main deployment function
main() {
    # 🔥 NEW: Deployment Lock Mechanism
    local lock_file="$DATA_ROOT/.deployment_lock"
    
    if [[ -f "$lock_file" ]]; then
        local lock_pid=$(cat "$lock_file" 2>/dev/null || echo "unknown")
        if ps -p "$lock_pid" >/dev/null 2>&1; then
            print_error "Deployment is already running (PID: $lock_pid)"
            print_error "Wait for it to complete or run: kill $lock_pid"
            exit 1
        else
            print_warning "Removing stale deployment lock"
            rm -f "$lock_file"
        fi
    fi
    
    # Create deployment lock
    echo $$ > "$lock_file"
    trap 'rm -f "$lock_file"' EXIT
    
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║            AI PLATFORM AUTOMATION - DEPLOYMENT                 ║${NC}"
    echo -e "${CYAN}║              Non-Root Version 7.0.0                      ║${NC}"
    echo -e "${CYAN}║           AppArmor Security & Complete Coverage              ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}\n"
    
    # 🔥 NEW: Comprehensive Cleanup Before Deployment
    print_info "Performing pre-deployment cleanup..."
    cleanup_previous_deployments
    
    # Load selected services from Script 1
    load_selected_services
    
    # Setup AppArmor security
    setup_apparmor_security
    
    # Create Docker network if not exists
    if ! docker network inspect ai_platform >/dev/null 2>&1; then
        docker network create ai_platform
        print_success "Created ai_platform network"
    fi
    
    # Deploy all selected services
    local deployed=0
    local failed=0
    
    for service in "${SELECTED_SERVICES[@]}"; do
        print_info "Deploying service: $service"
        
        if deploy_service "$service"; then
            deployed=$((deployed + 1))
        else
            failed=$((failed + 1))
        fi
    done
    
    echo -e "\n${GREEN}🎉 Deployment completed!${NC}"
    echo -e "${CYAN}✅ Deployed: $deployed services${NC}"
    echo -e "${RED}❌ Failed: $failed services${NC}"
    echo -e "${CYAN}All containers are running as non-root user with AppArmor security${NC}"
    echo -e "${CYAN}Check container status: docker ps --format 'table {{.Names}}\t{{.User}}\t{{.Status}}'${NC}"
}

# Run main function
main "$@"
