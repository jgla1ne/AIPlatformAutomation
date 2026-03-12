#!/usr/bin/env bash
# =============================================================================
# Script 3: Configure Services - Mission Control
# =============================================================================
set -eo pipefail

# --- Color Definitions ---
DIM="${DIM:-\033[2m}"
NC="${NC:-\033[0m}"
RED="${RED:-\033[0;31m}"
GREEN="${GREEN:-\033[0;32m}"
YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"
BLUE="${BLUE:-\033[0;34m}"
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
    local action="${2:---health}" # Default to --health if no action provided
    
    if [[ -z "$tenant_id" ]]; then
        echo "Usage: sudo bash $0 <tenant_id> [action]"
        echo ""
        echo "Actions:"
        echo "  configure  - Configure logging for all services (default)"
        echo "  disable    - Disable logging for all services"
        echo "  rotate    - Rotate service logs"
        echo "  cleanup    - Clean up old logs"
        echo "  dashboard  - Show logging dashboard"
        echo "  start      - Start specific service (or all)"
        echo "  stop       - Stop specific service (or all)"
        echo "  rclone-mount - Execute docker exec to start Rclone mount"
        echo "  ingest     - Execute tenant's ingest.py script"
        echo "  pair-signal - Generate QR code for Signal device pairing"
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
        "--health")
            log "Running comprehensive health checks for tenant: ${TENANT_ID}"
            ;;
        "cleanup")
            log "Cleaning up old logs..."
            cleanup_old_logs
            ;;
        "pair-signal")
            log "Generating QR code for Signal device pairing..."
            pair_signal_device
            ;;
        "dashboard")
            show_logging_dashboard
            ;;
        "start")
            log "Starting services for tenant: ${TENANT_ID}"
            cd "${TENANT_DIR}"
            if [[ -n "${2:-}" ]]; then
                docker compose start "$2"
                ok "Service '$2' started."
            else
                docker compose start
                ok "All services started."
            fi
            ;;
        "stop")
            log "Stopping services for tenant: ${TENANT_ID}"
            cd "${TENANT_DIR}"
            if [[ -n "${2:-}" ]]; then
                docker compose stop "$2"
                ok "Service '$2' stopped."
            else
                docker compose stop
                ok "All services stopped."
            fi
            ;;
        "rclone-mount")
            log "Starting Rclone mount for tenant: ${TENANT_ID}"
            cd "${TENANT_DIR}"
            docker exec -d "$(docker ps -q --filter "name=rclone" 2>/dev/null || echo "")" \
                rclone mount gdrive: /mnt/gdrive --vfs-cache-mode writes &
            ok "Rclone mount started in background."
            ;;
        "ingest")
            log "Starting data ingestion for tenant: ${TENANT_ID}"
            cd "${TENANT_DIR}"
            # Run ingestion using temporary networked container
            docker run --rm --network "${TENANT_ID}_default" \
                -v "${TENANT_DIR}/ingest.py:/app/ingest.py" \
                python:3.9-slim python /app/ingest.py
            ok "Data ingestion completed."
            ;;
        "health")
            log "Running comprehensive health checks for tenant: ${TENANT_ID}"
            
            # 1. Container Status Check
            log "=== CONTAINER STATUS CHECK ==="
            cd "${TENANT_DIR}"
            docker compose ps
            
            # 2. External Port Check
            log "=== EXTERNAL PORT CONNECTIVITY ==="
            nc -z localhost "${CADDY_HTTP_PORT:-80}" && ok "HTTP port 80 accessible" || fail "HTTP port 80 NOT accessible"
            nc -z localhost "${CADDY_HTTPS_PORT:-443}" && ok "HTTPS port 443 accessible" || fail "HTTPS port 443 NOT accessible"
            
            # 3. External URL Check
            log "=== EXTERNAL URL ACCESSIBILITY ==="
            if [[ -n "${DOMAIN:-}" ]]; then
                curl --silent --fail https://"${DOMAIN}" > /dev/null && ok "Main domain accessible" || fail "Main domain NOT accessible"
                curl --silent --fail https://grafana."${DOMAIN}" > /dev/null && ok "Grafana accessible" || warn "Grafana not accessible"
                curl --silent --fail https://openwebui."${DOMAIN}" > /dev/null && ok "OpenWebUI accessible" || warn "OpenWebUI not accessible"
            fi
            
            # 4. Internal Integration Check
            log "=== INTERNAL INTEGRATION CHECK ==="
            
            # Test OpenWebUI -> LiteLLM
            if docker ps -q --filter "name=openwebui" | grep -q .; then
                if docker exec "$(docker ps -q --filter "name=openwebui")" curl --fail --silent --connect-timeout 5 http://litellm:4000 > /dev/null; then
                    ok "Integration: OpenWebUI → LiteLLM"
                else
                    fail "Integration FAILED: OpenWebUI → LiteLLM"
                fi
            fi
            
            # Test LiteLLM -> Ollama
            if docker ps -q --filter "name=litellm" | grep -q .; then
                if docker exec "$(docker ps -q --filter "name=litellm")" curl --fail --silent --connect-timeout 5 http://ollama:11434 > /dev/null; then
                    ok "Integration: LiteLLM → Ollama"
                else
                    fail "Integration FAILED: LiteLLM → Ollama"
                fi
            fi
            
            # Test Flowise -> Postgres
            if docker ps -q --filter "name=flowise" | grep -q .; then
                if docker exec "$(docker ps -q --filter "name=flowise")" nc -z postgres 5432 > /dev/null; then
                    ok "Integration: Flowise → Postgres"
                else
                    fail "Integration FAILED: Flowise → Postgres"
                fi
            fi
            
            log "=== ULTIMATE VERIFICATION COMPLETE ==="
            
            # 5. Service Health Summary
            log "=== HEALTH SUMMARY ==="
            local total_containers=$(docker ps --filter "name=${COMPOSE_PROJECT_NAME}" --format "{{.Names}}" | wc -l)
            local running_containers=$(docker ps --filter "name=${COMPOSE_PROJECT_NAME}" --filter "status=running" --format "{{.Names}}" | wc -l)
            log "Total containers: ${total_containers}"
            log "Running containers: ${running_containers}"
            
            if [[ $running_containers -eq $total_containers ]]; then
                ok "All containers are running!"
            else
                warn "Some containers are not running."
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
    esac
}

# --- Signal Device Pairing Function ---
pair_signal_device() {
    log "Generating QR code for Signal device pairing..."
    
    # Check if signal container is running
    local signal_container="${COMPOSE_PROJECT_NAME}-signal-1"
    if ! docker ps --filter "name=${signal_container}" --filter "status=running" | grep -q "${signal_container}"; then
        fail "Signal container is not running. Please start Signal service first."
    fi
    
    # Generate device name
    local device_name="${TENANT_ID}-ai-platform"
    
    log "Generating pairing link for device: ${device_name}"
    
    # Get QR code link from Signal API
    local pairing_response=$(curl -s "http://localhost:8080/v1/qrcodelink?device_name=${device_name}")
    
    if [[ -z "$pairing_response" ]]; then
        fail "Failed to get pairing link from Signal API"
    fi
    
    # Extract the URI from response
    local tsdevice_uri=$(echo "$pairing_response" | grep -o 'tsdevice:/[^"]*')
    
    if [[ -z "$tsdevice_uri" ]]; then
        fail "Failed to extract pairing URI from response"
    fi
    
    log "Pairing URI generated: ${tsdevice_uri}"
    
    # Check if qrencode is available
    if ! command -v qrencode &> /dev/null; then
        warn "qrencode not found. Installing..."
        apt-get update && apt-get install -y qrencode || {
            fail "Failed to install qrencode. Please install it manually."
        }
    fi
    
    # Generate QR code
    log "Generating QR code for scanning..."
    echo ""
    echo "=================================================================="
    echo "📱 SCAN THIS QR CODE WITH YOUR SIGNAL APP 📱"
    echo "=================================================================="
    echo ""
    qrencode -t ANSI "${tsdevice_uri}"
    echo ""
    echo "=================================================================="
    echo "📱 Open Signal App → Settings → Linked Devices → '+' → Scan QR Code"
    echo "=================================================================="
    echo ""
    
    # Store pairing confirmation
    local paired_file="${TENANT_DIR}/signal-data/.paired"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Device ${device_name} paired with URI: ${tsdevice_uri}" > "$paired_file"
    chown "${TENANT_UID}:${TENANT_GID}" "$paired_file"
    
    ok "QR code generated successfully!"
    ok "Pairing URI saved to: ${paired_file}"
    ok "After scanning, Signal service will be fully operational."
    
    # Wait a moment for user to scan
    log "Waiting for device pairing to complete..."
    sleep 10
    
    # Verify pairing was successful
    log "Verifying Signal service health..."
    local health_check=$(curl -s "http://localhost:8080/v1/about" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
    
    if [[ "$health_check" == "ok" ]]; then
        ok "✅ Signal service is healthy and ready!"
        ok "✅ OpenClaw can now be started successfully."
    else
        warn "⚠️  Signal service may still be initializing..."
        warn "⚠️  Check service logs with: docker compose logs signal"
    fi
}

# Call main function to execute the script
main "$@"
