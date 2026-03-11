#!/usr/bin/env bash
# =============================================================================
# Script 3: Configure Services - INDIVIDUAL LOGGING ENGINE
# =============================================================================
set -euo pipefail

# --- Colors and Logging ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'
log() { echo -e "${CYAN}[INFO]${NC}    $1"; }
ok() { echo -e "${GREEN}[OK]${NC}      $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}    $*"; }
fail() { echo -e "${RED}[FAIL]${NC}    $*"; exit 1; }

# --- Tenant ID Check ---
if [[ -z "${1:-}" ]] && [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: TENANT_ID is required. Usage: sudo bash $0 <tenant_id>" >&2
    exit 1
fi
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    TENANT_ID="$1"
fi

# --- Environment Setup ---
if [[ -n "${TENANT_ID:-}" ]]; then
    TENANT_DIR="/mnt/data/${TENANT_ID}"
    ENV_FILE="${TENANT_DIR}/.env"
    if [[ ! -f "${ENV_FILE}" ]]; then
        fail "Environment file not found for tenant '${TENANT_ID}' at ${ENV_FILE}"
    fi
    log "Loading environment from: ${ENV_FILE}"
    set -a
    source "${ENV_FILE}" 2>/dev/null || true
    set +a
    DATA_ROOT="${TENANT_DIR}"
fi

# --- Service Log Configuration Functions ---
configure_service_logging() {
    local service=$1
    local enable_logs="${2:-true}"
    local log_level="${3:-info}"
    local log_retention="${4:-7}"  # days
    
    local service_log_dir="${TENANT_DIR}/${service}/logs"
    local service_config_file="${TENANT_DIR}/${service}/logging.conf"
    
    log "=== CONFIGURING LOGGING FOR $service ==="
    
    # Create service log directory
    mkdir -p "$service_log_dir"
    chown "${TENANT_UID:-1001}:${TENANT_GID:-1001}" "$service_log_dir"
    
    if [[ "$enable_logs" == "true" ]]; then
        log "Enabling logging for $service with level: $log_level"
        
        # Create service-specific logging configuration
        cat > "$service_config_file" << EOF
# Service Logging Configuration for $service
# Generated: $(date)
ENABLE_LOGGING=true
LOG_LEVEL=$log_level
LOG_RETENTION_DAYS=$log_retention
LOG_DIR=$service_log_dir
LOG_ROTATION=true
LOG_MAX_SIZE=100M
LOG_FORMAT=json
EOF
        
        # Update .env with service-specific logging variables
        case "$service" in
            "postgres")
                echo "POSTGRES_LOGGING_ENABLED=true" >> "${ENV_FILE}"
                echo "POSTGRES_LOG_DIR=$service_log_dir" >> "${ENV_FILE}"
                echo "POSTGRES_LOG_LEVEL=$log_level" >> "${ENV_FILE}"
                echo "POSTGRES_LOG_ROTATION=true" >> "${ENV_FILE}"
                ;;
            "redis")
                echo "REDIS_LOGGING_ENABLED=true" >> "${ENV_FILE}"
                echo "REDIS_LOG_DIR=$service_log_dir" >> "${ENV_FILE}"
                echo "REDIS_LOGLEVEL=$log_level" >> "${ENV_FILE}"
                ;;
            "qdrant")
                echo "QDRANT_LOGGING_ENABLED=true" >> "${ENV_FILE}"
                echo "QDRANT_LOG_DIR=$service_log_dir" >> "${ENV_FILE}"
                echo "QDRANT__LOG_LEVEL=$log_level" >> "${ENV_FILE}"
                ;;
            "grafana")
                echo "GRAFANA_LOGGING_ENABLED=true" >> "${ENV_FILE}"
                echo "GRAFANA_LOG_DIR=$service_log_dir" >> "${ENV_FILE}"
                echo "GF_LOG_LEVEL=$log_level" >> "${ENV_FILE}"
                echo "GF_LOG_MODE=console file" >> "${ENV_FILE}"
                echo "GF_PATHS_LOGS=$service_log_dir" >> "${ENV_FILE}"
                ;;
            "prometheus")
                echo "PROMETHEUS_LOGGING_ENABLED=true" >> "${ENV_FILE}"
                echo "PROMETHEUS_LOG_DIR=$service_log_dir" >> "${ENV_FILE}"
                echo "PROMETHEUS_LOG_LEVEL=$log_level" >> "${ENV_FILE}"
                echo "PROMETHEUS_LOG_FORMAT=json" >> "${ENV_FILE}"
                ;;
            "caddy")
                echo "CADDY_LOGGING_ENABLED=true" >> "${ENV_FILE}"
                echo "CADDY_LOG_DIR=$service_log_dir" >> "${ENV_FILE}"
                echo "CADDY_LOG_LEVEL=$log_level" >> "${ENV_FILE}"
                echo "CADDY_LOG_FORMAT=json" >> "${ENV_FILE}"
                ;;
        esac
        
        ok "Logging enabled for $service -> $service_log_dir"
    else
        log "Disabling logging for $service"
        echo "POSTGRES_LOGGING_ENABLED=false" >> "${ENV_FILE}"
        echo "REDIS_LOGGING_ENABLED=false" >> "${ENV_FILE}"
        echo "QDRANT_LOGGING_ENABLED=false" >> "${ENV_FILE}"
        echo "GRAFANA_LOGGING_ENABLED=false" >> "${ENV_FILE}"
        echo "PROMETHEUS_LOGGING_ENABLED=false" >> "${ENV_FILE}"
        echo "CADDY_LOGGING_ENABLED=false" >> "${ENV_FILE}"
        warn "Logging disabled for $service"
    fi
    
    log "=== END LOGGING CONFIGURATION FOR $service ==="
}

# --- Health Check Functions ---
check_service_health() {
    local service=$1
    local health_url=$2
    local timeout=${3:-10}
    
    log "Checking health for $service..."
    
    if curl -s -f --max-time "$timeout" "$health_url" >/dev/null 2>&1; then
        ok "$service is healthy"
        return 0
    else
        warn "$service is unhealthy or not responding"
        return 1
    fi
}

check_port_connectivity() {
    local port=$1
    local service=$2
    local timeout=${3:-5}
    
    if nc -z -w "$timeout" localhost "$port" 2>/dev/null; then
        ok "$service (port $port) is accessible"
        return 0
    else
        warn "$service (port $port) is not accessible"
        return 1
    fi
}

# --- URL Testing Functions ---
test_internal_urls() {
    log "=== TESTING INTERNAL URLS ==="
    
    local internal_tests=(
        "postgres:5432:nc"
        "redis:6379:nc"
        "qdrant:6333/health:http"
        "grafana:3000/api/health:http"
        "prometheus:9090/-/healthy:http"
        "caddy:80:http"
    )
    
    for test in "${internal_tests[@]}"; do
        IFS=':' read -r service port_or_path method <<< "$test"
        
        case "$method" in
            "nc")
                check_port_connectivity "$port_or_path" "$service"
                ;;
            "http")
                check_service_health "$service" "http://localhost:$port_or_path"
                ;;
        esac
    done
    
    log "=== END INTERNAL URL TESTING ==="
}

test_external_urls() {
    log "=== TESTING EXTERNAL URLS ==="
    
    if [[ -n "${DOMAIN:-}" ]]; then
        local external_tests=(
            "https://${DOMAIN}:main"
            "https://grafana.${DOMAIN}:grafana"
            "https://prometheus.${DOMAIN}:prometheus"
            "https://auth.${DOMAIN}:authentik"
        )
        
        for test in "${external_tests[@]}"; do
            IFS=':' read -r url service <<< "$test"
            
            if curl -s -f --max-time 10 "$url" >/dev/null 2>&1; then
                ok "$service ($url) is reachable"
            else
                warn "$service ($url) is not reachable"
            fi
        done
    else
        warn "DOMAIN not set, skipping external URL tests"
    fi
    
    log "=== END EXTERNAL URL TESTING ==="
}

# --- Log Management Functions ---
rotate_service_logs() {
    local service=$1
    local service_log_dir="${TENANT_DIR}/${service}/logs"
    
    if [[ -d "$service_log_dir" ]]; then
        log "Rotating logs for $service..."
        
        # Compress logs older than 1 day
        find "$service_log_dir" -name "*.log" -mtime +1 -exec gzip {} \;
        
        # Remove compressed logs older than retention period
        find "$service_log_dir" -name "*.log.gz" -mtime +7 -delete
        
        ok "Log rotation completed for $service"
    fi
}

cleanup_old_logs() {
    log "=== CLEANING UP OLD LOGS ==="
    
    # Clean up deployment logs older than 30 days
    find "${TENANT_DIR}/logs" -name "deploy-*.log" -mtime +30 -delete
    
    # Clean up service logs older than retention period
    for service in postgres redis qdrant grafana prometheus caddy; do
        rotate_service_logs "$service"
    done
    
    ok "Log cleanup completed"
    log "=== END LOG CLEANUP ==="
}

# --- Dashboard Functions ---
show_logging_dashboard() {
    log "=== LOGGING DASHBOARD ==="
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════════╗"
    echo "║                      🗂 SERVICE LOGGING DASHBOARD                           ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    printf "%-15s %-12s %-25s %-15s %-10s\n" "SERVICE" "ENABLED" "LOG_DIR" "LEVEL" "RETENTION"
    printf "%-15s %-12s %-25s %-15s %-10s\n" "--------" "-------" "--------" "-----" "---------"
    
    services=("postgres" "redis" "qdrant" "grafana" "prometheus" "caddy")
    
    for service in "${services[@]}"; do
        local enabled_var="${service^^}_LOGGING_ENABLED"
        local enabled="${!enabled_var:-false}"
        local log_dir="${TENANT_DIR}/${service}/logs"
        local level_var="${service^^}_LOG_LEVEL"
        local level="${!level_var:-info}"
        local retention="7 days"
        
        if [[ "$enabled" == "true" ]]; then
            printf "%-15s %-12s %-25s %-15s %-10s\n" "$service" "✅ YES" "$log_dir" "$level" "$retention"
        else
            printf "%-15s %-12s %-25s %-15s %-10s\n" "$service" "❌ NO" "N/A" "N/A" "N/A"
        fi
    done
    
    echo ""
    echo "📋 LOG LOCATIONS:"
    echo "   • Main deployment logs: ${TENANT_DIR}/logs/deploy-*.log"
    echo "   • Service logs: ${TENANT_DIR}/*/logs/"
    echo ""
    echo "🔧 LOG MANAGEMENT:"
    echo "   • Rotate logs: sudo bash $0 ${TENANT_ID} --rotate"
    echo "   • Clean logs: sudo bash $0 ${TENANT_ID} --cleanup"
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════════╗"
    echo "║                      END LOGGING DASHBOARD                                   ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    log "=== END LOGGING DASHBOARD ==="
}

# --- Main Function ---
main() {
    local tenant_id="${1:-}"
    local action="${2:-configure}"
    
    if [[ -z "$tenant_id" ]]; then
        echo "Usage: sudo bash $0 <tenant_id> [action]"
        echo ""
        echo "Actions:"
        echo "  configure  - Configure logging for all services (default)"
        echo "  disable    - Disable logging for all services"
        echo "  rotate    - Rotate service logs"
        echo "  cleanup    - Clean up old logs"
        echo "  dashboard  - Show logging dashboard"
        echo "  health     - Run comprehensive health checks"
        exit 1
    fi
    
    # Set global tenant ID for the script
    TENANT_ID="$tenant_id"
    
    case "$action" in
        "configure")
            log "Starting service logging configuration..."
            
            # Configure logging for all enabled services
            [[ "${ENABLE_POSTGRES}" == "true" ]] && configure_service_logging "postgres" "true" "info"
            [[ "${ENABLE_REDIS}" == "true" ]] && configure_service_logging "redis" "true" "notice"
            [[ "${ENABLE_QDRANT}" == "true" ]] && configure_service_logging "qdrant" "true" "info"
            [[ "${ENABLE_GRAFANA}" == "true" ]] && configure_service_logging "grafana" "true" "info"
            [[ "${ENABLE_PROMETHEUS}" == "true" ]] && configure_service_logging "prometheus" "true" "info"
            [[ "${ENABLE_CADDY}" == "true" ]] && configure_service_logging "caddy" "true" "info"
            
            # Show logging dashboard
            show_logging_dashboard
            
            ok "Service logging configuration completed."
            ;;
        "disable")
            log "Disabling logging for all services..."
            
            # Disable logging for all services
            for service in postgres redis qdrant grafana prometheus caddy; do
                configure_service_logging "$service" "false"
            done
            
            ok "Logging disabled for all services."
            ;;
        "rotate")
            log "Rotating service logs..."
            cleanup_old_logs
            ;;
        "cleanup")
            log "Cleaning up old logs..."
            cleanup_old_logs
            ;;
        "dashboard")
            show_logging_dashboard
            ;;
        "health")
            log "Running comprehensive health checks for tenant: ${TENANT_ID}"
            
            # 1. Check Container Status
            log "=== CONTAINER STATUS ==="
            cd "${TENANT_DIR}"
            docker ps --filter "name=${COMPOSE_PROJECT_NAME}"
            
            # 2. Test Port Connectivity
            log "=== PORT CONNECTIVITY TESTS ==="
            nc -z localhost "${POSTGRES_PORT:-5432}" && ok "PostgreSQL port ${POSTGRES_PORT:-5432} is open." || warn "PostgreSQL port is closed."
            nc -z localhost "${REDIS_PORT:-6379}" && ok "Redis port ${REDIS_PORT:-6379} is open." || warn "Redis port is closed."
            nc -z localhost "${QDRANT_PORT:-6333}" && ok "Qdrant port ${QDRANT_PORT:-6333} is open." || warn "Qdrant port is closed."
            
            # 3. Test URL Accessibility (Internal and External)
            log "=== URL ACCESSIBILITY TESTS ==="
            curl --silent --fail http://localhost:${OLLAMA_PORT:-11434}/api/tags > /dev/null && ok "Ollama API is responsive." || warn "Ollama API is not responsive."
            curl --silent --fail http://localhost:${QDRANT_PORT:-6333} > /dev/null && ok "Qdrant API is responsive." || warn "Qdrant API is not responsive."
            curl --silent --fail http://localhost:80 > /dev/null && ok "Caddy HTTP is responsive." || warn "Caddy HTTP is not responsive."
            
            if [[ -n "${DOMAIN:-}" ]]; then
                curl --silent --fail https://grafana.${DOMAIN} > /dev/null && ok "Grafana URL is accessible." || warn "Grafana URL is not accessible."
                curl --silent --fail https://prometheus.${DOMAIN} > /dev/null && ok "Prometheus URL is accessible." || warn "Prometheus URL is not accessible."
                curl --silent --fail https://${DOMAIN} > /dev/null && ok "Main domain URL is accessible." || warn "Main domain URL is not accessible."
            fi
            
            # 4. Service Health Summary
            log "=== HEALTH SUMMARY ==="
            local total_containers=$(docker ps --filter "name=${COMPOSE_PROJECT_NAME}" --format "{{.Names}}" | wc -l)
            local running_containers=$(docker ps --filter "name=${COMPOSE_PROJECT_NAME}" --filter "status=running" --format "{{.Names}}" | wc -l)
            log "Total containers: ${total_containers}"
            log "Running containers: ${running_containers}"
            
            if [[ $running_containers -eq $total_containers ]]; then
                ok "All containers are running!"
            else
                warn "Some containers may not be running properly."
            fi
            
            log "Health check complete."
            ;;
        *)
            echo "Usage: sudo bash $0 <tenant_id> [action]"
            echo ""
            echo "Actions:"
            echo "  configure  - Configure logging for all services (default)"
            echo "  disable    - Disable logging for all services"
            echo "  rotate    - Rotate service logs"
            echo "  cleanup    - Clean up old logs"
            echo "  dashboard  - Show logging dashboard"
            echo "  health     - Run comprehensive health checks"
            exit 1
            ;;
    esac
}

# Call main function to execute the script
main "$@"
