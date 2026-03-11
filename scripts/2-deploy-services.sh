#!/usr/bin/env bash
# =============================================================================
# Script 2: Deploy Services - COMPREHENSIVE DEBUG LOGGING ENGINE (DEBUG BY DEFAULT)
# =============================================================================
# Usage: sudo bash 2-deploy-services.sh [tenant_id]
# Default tenant: datasquiz
# Debug mode: ENABLED BY DEFAULT
# Output: All logs piped to single timestamped file
# =============================================================================
set -euo pipefail

# --- DEBUG MODE FLAG - DEBUG ENABLED BY DEFAULT ---
DEBUG_MODE="${DEBUG_MODE:-true}"
if [[ "${DEBUG_MODE}" == "true" ]]; then
    set -x
fi

# --- Colors and Logging ---
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' BLUE='\033[0;34m' NC='\033[0m'
LOG_FILE=""  # Initialize LOG_FILE early

log() { 
    if [[ -n "${LOG_FILE}" ]]; then
        echo -e "${CYAN}[INFO]${NC}    $1" | tee -a "${LOG_FILE}"
    else
        echo -e "${CYAN}[INFO]${NC}    $1"
    fi
}
ok() { 
    if [[ -n "${LOG_FILE}" ]]; then
        echo -e "${GREEN}[OK]${NC}      $*" | tee -a "${LOG_FILE}"
    else
        echo -e "${GREEN}[OK]${NC}      $*"
    fi
}
warn() { 
    if [[ -n "${LOG_FILE}" ]]; then
        echo -e "${YELLOW}[WARN]${NC}    $*" | tee -a "${LOG_FILE}"
    else
        echo -e "${YELLOW}[WARN]${NC}    $*"
    fi
}
fail() { 
    if [[ -n "${LOG_FILE}" ]]; then
        echo -e "${RED}[FAIL]${NC}    $*" | tee -a "${LOG_FILE}"
    else
        echo -e "${RED}[FAIL]${NC}    $*"
    fi
    exit 1
}

# --- Deep Logging Functions ---
enable_service_debug_logging() {
    local service=$1
    local log_level="${2:-debug}"
    
    log "=== ENABLING DEBUG LOGGING FOR $service ==="
    
    # Add debug environment variables to .env
    case "$service" in
        "postgres")
            echo "POSTGRES_LOG_LEVEL=$log_level" >> "${ENV_FILE}"
            echo "POSTGRES_LOG_MIN_DURATION_STATEMENT=0" >> "${ENV_FILE}"
            echo "POSTGRES_LOG_MIN_MESSAGES=debug5" >> "${ENV_FILE}"
            ;;
        "redis")
            echo "REDIS_LOGLEVEL=$log_level" >> "${ENV_FILE}"
            ;;
        "qdrant")
            echo "QDRANT__LOG_LEVEL=$log_level" >> "${ENV_FILE}"
            echo "QDRANT__SERVICE__HTTP__ENABLE_CORS=true" >> "${ENV_FILE}"
            ;;
        "grafana")
            echo "GF_LOG_LEVEL=$log_level" >> "${ENV_FILE}"
            echo "GF_LOG_MODE=console,file" >> "${ENV_FILE}"
            ;;
        "prometheus")
            echo "PROMETHEUS_LOG_LEVEL=$log_level" >> "${ENV_FILE}"
            echo "PROMETHEUS_LOG_FORMAT=json" >> "${ENV_FILE}"
            ;;
        "caddy")
            echo "CADDY_LOG_LEVEL=$log_level" >> "${ENV_FILE}"
            echo "CADDY_LOG_FORMAT=json" >> "${ENV_FILE}"
            ;;
    esac
    
    log "Debug logging enabled for $service with level: $log_level"
}

capture_docker_logs() {
    local service=$1
    local log_file="${TENANT_DIR}/logs/deploy-${service}-$(date +%Y%m%d-%H%M%S).log"
    
    log "=== CAPTURING DOCKER LOGS FOR $service ==="
    
    # Get container logs with maximum verbosity
    cd "${TENANT_DIR}"
    if docker compose logs "$service" --timestamps --follow --tail=100 > "$log_file" 2>&1 & then
        local log_pid=$!
        log "Started capturing logs for $service (PID: $log_pid) to $log_file"
        
        # Store PID for later reference
        echo "$log_pid" > "${TENANT_DIR}/logs/${service}-log-pid.txt"
        
        # Wait a bit to ensure logging starts
        sleep 2
        
        # Check if log file has content
        if [[ -s "$log_file" ]]; then
            log "✅ Successfully capturing logs for $service"
        else
            log "❌ Failed to capture logs for $service"
            kill $log_pid 2>/dev/null || true
        fi
    else
        log "❌ Failed to start log capture for $service"
    fi
}

verify_core_services() {
    log "=== VERIFYING CORE SERVICES HEALTH ==="
    local core_services=("postgres" "redis" "caddy")
    local all_healthy=true
    
    for service in "${core_services[@]}"; do
        log "Checking ${service} health..."
        local container_name="${COMPOSE_PROJECT_NAME}-${service}-1"
        
        # Wait up to 60 seconds for the service to become healthy
        for i in {1..12}; do
            local status=$(docker ps --filter "name=${container_name}" --format "{{.Status}}" 2>/dev/null || echo "not found")
            
            if [[ "$status" == *"healthy"* ]] || [[ "$status" == *"Up"* ]]; then
                ok "${service} is healthy and running."
                break
            elif [[ "$status" == *"Restarting"* ]]; then
                if [[ $i -eq 12 ]]; then
                    warn "${service} is still restarting after 60 seconds."
                    all_healthy=false
                fi
            elif [[ "$status" == *"Exited"* ]] || [[ "$status" == *"not found"* ]]; then
                if [[ $i -eq 12 ]]; then
                    fail "${service} failed to start. Status: ${status}"
                fi
            fi
            
            sleep 5
        done
        
        # Final status check
        local final_status=$(docker ps --filter "name=${container_name}" --format "{{.Status}}" 2>/dev/null || echo "not found")
        if [[ "$final_status" != *"Up"* ]]; then
            warn "${service} final status: ${final_status}"
            all_healthy=false
        fi
    done
    
    if [[ "$all_healthy" == "true" ]]; then
        ok "All core services are healthy!"
    else
        warn "Some core services may not be fully healthy. Check individual service logs."
    fi
    log "=== END CORE SERVICES VERIFICATION ==="
}

capture_initial_logs() {
    log "=== CAPTURING INITIAL SERVICE LOGS ==="
    
    for service in $(docker compose ps --services 2>/dev/null); do
        local container_name="${COMPOSE_PROJECT_NAME}-${service}-1"
        local service_log_file="${LOG_DIR}/deploy-${service}-initial.log"
        
        if docker ps --filter "name=${container_name}" --format "{{.Names}}" | grep -q "${container_name}"; then
            log "Capturing initial logs for ${service}..."
            docker logs "${container_name}" --tail 50 &> "${service_log_file}" 2>&1
            log "Initial logs for ${service} saved to ${service_log_file}"
        else
            log "Container ${container_name} not running, skipping log capture."
        fi
    done
    
    log "=== END INITIAL LOG CAPTURE ==="
}

# --- Tenant ID Setup - DEFAULT TO DATASQUIZ ---
TENANT_ID="${1:-datasquiz}"
log "Using tenant ID: ${TENANT_ID}"

# --- Environment Setup ---
TENANT_DIR="/mnt/data/${TENANT_ID}"
ENV_FILE="${TENANT_DIR}/.env"
COMPOSE_FILE="${TENANT_DIR}/docker-compose.yml"

if [[ ! -f "${ENV_FILE}" ]]; then
    fail "Environment file not found for tenant '${TENANT_ID}' at ${ENV_FILE}"
fi

log "Loading environment from: ${ENV_FILE}"
set -a
source "${ENV_FILE}"
set +a

# --- Logging to File ---
LOG_DIR="${TENANT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/deploy-$(date +%Y%m%d-%H%M%S).log"

# CRITICAL FIX: Redirect both stdout and stderr to log file for complete debug capture
exec > >(tee -a "${LOG_FILE}") 2>&1
log "All output is now logged to: ${LOG_FILE}"
log "DEBUG_MODE: ${DEBUG_MODE}"
log "Complete stdout and stderr redirection enabled for comprehensive debugging"

# --- Enable Debug Logging for All Services ---
log "=== ENABLING COMPREHENSIVE DEBUG LOGGING ==="
if [[ "${DEBUG_MODE}" == "true" ]]; then
    log "Debug mode enabled - enabling verbose logging for all services"
    
    # Enable debug for all enabled services
    [[ "${ENABLE_POSTGRES}" == "true" ]] && enable_service_debug_logging "postgres"
    [[ "${ENABLE_REDIS}" == "true" ]] && enable_service_debug_logging "redis"
    [[ "${ENABLE_QDRANT}" == "true" ]] && enable_service_debug_logging "qdrant"
    [[ "${ENABLE_GRAFANA}" == "true" ]] && enable_service_debug_logging "grafana"
    [[ "${ENABLE_PROMETHEUS}" == "true" ]] && enable_service_debug_logging "prometheus"
    [[ "${ENABLE_CADDY}" == "true" ]] && enable_service_debug_logging "caddy"
    
    log "Debug logging enabled for all services"
fi
log "=== END DEBUG LOGGING SETUP ==="

# --- Service Generation Functions ---
add_postgres() {
    cat >> "${COMPOSE_FILE}" << EOF

  postgres:
    image: postgres:15-alpine
    restart: unless-stopped
    user: "\${POSTGRES_UID:-70}:\${TENANT_GID:-1001}"
    networks:
      - default
    environment:
      POSTGRES_USER: "\${POSTGRES_USER}"
      POSTGRES_PASSWORD: "\${POSTGRES_PASSWORD}"
      POSTGRES_DB: "\${POSTGRES_DB}"
      POSTGRES_LOG_LEVEL: "\${POSTGRES_LOG_LEVEL:-info}"
      POSTGRES_LOG_MIN_DURATION_STATEMENT: "\${POSTGRES_LOG_MIN_DURATION_STATEMENT:-1000}"
      POSTGRES_LOG_MIN_MESSAGES: "\${POSTGRES_LOG_MIN_MESSAGES:-warning}"
    volumes:
      - \${TENANT_DIR}/postgres:/var/lib/postgresql/data
EOF
    ok "Added 'postgres' service."
}

add_redis() {
    cat >> "${COMPOSE_FILE}" << EOF

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    user: "\${REDIS_UID:-999}:\${TENANT_GID:-1001}"
    networks:
      - default
    command: redis-server --requirepass "\${REDIS_PASSWORD}" --loglevel "\${REDIS_LOGLEVEL:-notice}"
    volumes:
      - \${TENANT_DIR}/redis:/data
EOF
    ok "Added 'redis' service."
}

add_qdrant() {
    cat >> "${COMPOSE_FILE}" << EOF

  qdrant:
    image: qdrant/qdrant:latest
    restart: unless-stopped
    user: "${QDRANT_UID:-1000}:${TENANT_GID:-1001}"
    networks:
      - default
    environment:
      QDRANT__LOG_LEVEL: "\${QDRANT__LOG_LEVEL:-info}"
      QDRANT__SERVICE__HTTP__ENABLE_CORS: "\${QDRANT__SERVICE__HTTP__ENABLE_CORS:-true}"
    volumes:
      - \${TENANT_DIR}/qdrant:/qdrant/storage
EOF
    ok "Added 'qdrant' service."
}

add_grafana() {
    cat >> "${COMPOSE_FILE}" << EOF

  grafana:
    image: grafana/grafana:latest
    restart: unless-stopped
    user: "${GRAFANA_UID:-472}:${TENANT_GID:-1001}"
    networks:
      - default
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
      - GF_LOG_LEVEL=${GF_LOG_LEVEL:-info}
      - GF_LOG_MODE=${GF_LOG_MODE:-console,file}
    volumes:
      - \${TENANT_DIR}/grafana:/var/lib/grafana
EOF
    ok "Added 'grafana' service."
}

add_prometheus() {
    cat >> "${COMPOSE_FILE}" << EOF

  prometheus:
    image: prom/prometheus:latest
    restart: unless-stopped
    user: "${PROMETHEUS_UID:-65534}:${TENANT_GID:-1001}"
    networks:
      - default
    environment:
      - PROMETHEUS_LOG_LEVEL=${PROMETHEUS_LOG_LEVEL:-info}
      - PROMETHEUS_LOG_FORMAT=${PROMETHEUS_LOG_FORMAT:-json}
    volumes:
      - \${TENANT_DIR}/prometheus.yml:/etc/prometheus/prometheus.yml
      - \${TENANT_DIR}/prometheus-data:/prometheus
EOF
    ok "Added 'prometheus' service."
}

add_caddy() {
    cat >> "${COMPOSE_FILE}" << EOF

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    user: "${CADDY_UID:-1001}:${TENANT_GID:-1001}"
    networks:
      - default
    environment:
      - CADDY_LOG_LEVEL=${CADDY_LOG_LEVEL:-info}
      - CADDY_LOG_FORMAT=${CADDY_LOG_FORMAT:-json}
    volumes:
      - \${TENANT_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile
      - \${TENANT_DIR}/caddy/data:/data
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
EOF
    ok "Added 'caddy' service."
}

test_service_urls() {
    log "=== COMPREHENSIVE URL TESTING ==="
    
    local test_results=()
    
    # Test internal URLs
    test_results+=("INTERNAL: http://localhost:5432 - $(nc -z localhost 5432 && echo "✅ OPEN" || echo "❌ CLOSED")")
    test_results+=("INTERNAL: http://localhost:6379 - $(nc -z localhost 6379 && echo "✅ OPEN" || echo "❌ CLOSED")")
    test_results+=("INTERNAL: http://localhost:6333/health - $(curl -s -f http://localhost:6333/health >/dev/null 2>&1 && echo "✅ HEALTHY" || echo "❌ UNHEALTHY")")
    test_results+=("INTERNAL: http://localhost:3000/api/health - $(curl -s -f http://localhost:3000/api/health >/dev/null 2>&1 && echo "✅ HEALTHY" || echo "❌ UNHEALTHY")")
    test_results+=("INTERNAL: http://localhost:9090/-/healthy - $(curl -s -f http://localhost:9090/-/healthy >/dev/null 2>&1 && echo "✅ HEALTHY" || echo "❌ UNHEALTHY")")
    test_results+=("INTERNAL: http://localhost:80 - $(curl -s -f http://localhost:80 >/dev/null 2>&1 && echo "✅ HEALTHY" || echo "❌ UNHEALTHY")")
    
    # Test external URLs if DOMAIN is set
    if [[ -n "${DOMAIN:-}" ]]; then
        test_results+=("EXTERNAL: https://${DOMAIN} - $(curl -s -f https://${DOMAIN} >/dev/null 2>&1 && echo "✅ REACHABLE" || echo "❌ NOT REACHABLE")")
        test_results+=("EXTERNAL: https://grafana.${DOMAIN} - $(curl -s -f https://grafana.${DOMAIN} >/dev/null 2>&1 && echo "✅ REACHABLE" || echo "❌ NOT REACHABLE")")
        test_results+=("EXTERNAL: https://prometheus.${DOMAIN} - $(curl -s -f https://prometheus.${DOMAIN} >/dev/null 2>&1 && echo "✅ REACHABLE" || echo "❌ NOT REACHABLE")")
    fi
    
    # Log all test results
    for result in "${test_results[@]}"; do
        log "URL TEST: $result"
    done
    
    log "=== END URL TESTING ==="
}

prepare_data_directories() {
    log "INFO" "Enforcing Bulletproof Ownership as per README.md..."

    # Ensure base directory and logs are owned by the tenant user first
    chown -R "${TENANT_UID}:${TENANT_GID}" "${TENANT_DIR}"
    
    # Create all potential stateful directories
    mkdir -p "${TENANT_DIR}/postgres" "${TENANT_DIR}/redis" "${TENANT_DIR}/qdrant" \
             "${TENANT_DIR}/grafana" "${TENANT_DIR}/prometheus" \
             "${TENANT_DIR}/caddy/data" "${TENANT_DIR}/caddy/config"

    # Use the EXACT UIDs from the .env file to set ownership.
    # This aligns with the "Pragmatic Exception Pattern" from the README.
    [[ -d "${TENANT_DIR}/postgres" ]]   && chown -R "${POSTGRES_UID}:${TENANT_GID}"   "${TENANT_DIR}/postgres"   && ok "Ownership set for Postgres (${POSTGRES_UID}:${TENANT_GID})"
    [[ -d "${TENANT_DIR}/redis" ]]      && chown -R "${REDIS_UID}:${TENANT_GID}"      "${TENANT_DIR}/redis"      && ok "Ownership set for Redis (${REDIS_UID}:${TENANT_GID})"
    [[ -d "${TENANT_DIR}/qdrant" ]]      && chown -R "${QDRANT_UID}:${TENANT_GID}"      "${TENANT_DIR}/qdrant"      && ok "Ownership set for Qdrant (${QDRANT_UID}:${TENANT_GID})"
    [[ -d "${TENANT_DIR}/grafana" ]]     && chown -R "${GRAFANA_UID}:${TENANT_GID}"     "${TENANT_DIR}/grafana"    && ok "Ownership set for Grafana (${GRAFANA_UID}:${TENANT_GID})"
    [[ -d "${TENANT_DIR}/prometheus" ]] && chown -R "${PROMETHEUS_UID}:${TENANT_GID}" "${TENANT_DIR}/prometheus" && ok "Ownership set for Prometheus (${PROMETHEUS_UID}:${TENANT_GID})"
    [[ -d "${TENANT_DIR}/caddy" ]]       && chown -R "${CADDY_UID}:${TENANT_GID}"       "${TENANT_DIR}/caddy"      && ok "Ownership set for Caddy (${CADDY_UID}:${TENANT_GID})"

    log "SUCCESS" "Bulletproof Ownership check complete. All directory permissions are aligned with service UIDs."
}

# --- Main Function ---
main() {
    # --- Docker Check ---
    if ! docker info &>/dev/null; then
        fail "Docker is not running. Please start Docker and try again."
    fi
    ok "Docker is active."

    # --- Generate Docker Compose ---
    log "Generating docker-compose.yml for tenant '${TENANT_ID}'..."

    # Initialize compose file
    cat > "${COMPOSE_FILE}" << 'EOF'
services:
EOF

    # --- Generate All Services ---
    [[ "${ENABLE_POSTGRES}" == "true" ]] && add_postgres
    [[ "${ENABLE_REDIS}" == "true" ]] && add_redis
    [[ "${ENABLE_QDRANT}" == "true" ]] && add_qdrant
    [[ "${ENABLE_GRAFANA}" == "true" ]] && add_grafana
    [[ "${ENABLE_PROMETHEUS}" == "true" ]] && add_prometheus
    add_caddy # Caddy is always added

    # --- Add Network Configuration ---
    cat >> "${COMPOSE_FILE}" << 'EOF'

networks:
  default:
    name: ${DOCKER_NETWORK}
    driver: bridge
EOF

    # --- Deploy Services ---
    log "Starting deployment with docker compose..."
    cd "${TENANT_DIR}"

    log "=== DOCKER COMPOSE DEBUG INFO ==="
    log "Current directory: $(pwd)"
    log "Docker compose file: ${COMPOSE_FILE}"
    log "Docker compose file exists: $([ -f "${COMPOSE_FILE}" ] && echo "YES" || echo "NO")"
    
    if [[ -f "${COMPOSE_FILE}" ]]; then
        log "Docker compose file size: $(wc -l < "${COMPOSE_FILE}") lines"
        log "Docker compose file permissions: $(ls -la "${COMPOSE_FILE}")"
        log "=== DOCKER COMPOSE FILE CONTENT ==="
        cat "${COMPOSE_FILE}" >> "${LOG_FILE}" 2>&1
        log "=== END DOCKER COMPOSE FILE ==="
    fi

    log "=== DOCKER SYSTEM INFO ==="
    docker system info >> "${LOG_FILE}" 2>&1
    log "=== END DOCKER SYSTEM INFO ==="

    log "Pulling all required Docker images..."
    docker compose pull --quiet >> "${LOG_FILE}" 2>&1

    # Prepare data directories with correct permissions
    prepare_data_directories

    log "Starting all services in detached mode..."
    log "Executing docker compose up -d... Output logged to ${LOG_FILE}"
    if ! docker compose up -d >> "${LOG_FILE}" 2>&1; then
        log "=== DEPLOYMENT FAILURE DEBUG ==="
        log "Docker compose logs:"
        docker compose logs --tail=50 >> "${LOG_FILE}" 2>&1
        log "=== END DEPLOYMENT FAILURE DEBUG ==="
        fail "Docker Compose failed to start. Please check the logs above."
    fi

    # Wait for services to initialize
    log "Waiting for services to initialize..."
    sleep 10

    # Verify core services health
    verify_core_services

    # Capture initial service logs
    capture_initial_logs

    # Start deep log capture for all services if in debug mode
    if [[ "${DEBUG_MODE}" == "true" ]]; then
        log "=== STARTING DEEP LOG CAPTURE ==="
        [[ "${ENABLE_POSTGRES}" == "true" ]] && capture_docker_logs "postgres"
        [[ "${ENABLE_REDIS}" == "true" ]] && capture_docker_logs "redis"
        [[ "${ENABLE_QDRANT}" == "true" ]] && capture_docker_logs "qdrant"
        [[ "${ENABLE_GRAFANA}" == "true" ]] && capture_docker_logs "grafana"
        [[ "${ENABLE_PROMETHEUS}" == "true" ]] && capture_docker_logs "prometheus"
        [[ "${ENABLE_CADDY}" == "true" ]] && capture_docker_logs "caddy"
        log "=== DEEP LOG CAPTURE STARTED ==="
    fi

    # Comprehensive URL testing
    test_service_urls

    # Final status
    log "=== FINAL DEPLOYMENT STATUS ==="
    docker compose ps >> "${LOG_FILE}" 2>&1
    log "=== END FINAL DEPLOYMENT STATUS ==="

    ok "Deployment completed with comprehensive logging engine."
    log "Debug logs available in: ${LOG_DIR}/deploy-*.log"
    log "Service-specific logs available in: ${LOG_DIR}/deploy-<service>-*.log"
    log "Next Step: Run 'sudo bash scripts/3-configure-services.sh ${TENANT_ID}'"
}

# Call main function to execute the script
main
