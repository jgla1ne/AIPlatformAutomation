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
        echo "  provision  - Phase 3: Database provisioning, configuration verification, and health dashboard"
        echo "  disable    - Disable logging for all services"
        echo "  rotate    - Rotate service logs"
        echo "  cleanup    - Clean up old logs"
        echo "  dashboard  - Show logging dashboard"
        echo "  start      - Start specific service (or all)"
        echo "  stop       - Stop specific service (or all)"
        echo "  rclone-mount - Execute docker exec to start Rclone mount"
        echo "  ingest     - Execute tenant's ingest.py script"
        echo "  pair-signal - Generate QR code for Signal device pairing"
        echo "  tailscale   - Configure Tailscale VPN and display IP"
        echo "  health     - Run comprehensive health checks"
        echo "  dashboard  - Show comprehensive health dashboard"
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
        "provision")
            log "Starting Phase 3: Database provisioning and verification..."
            
            # Phase 3: Database provisioning
            provision_databases
            
            # Phase 3: Configuration verification
            verify_service_configurations
            
            # Phase 3: Health dashboard
            print_health_dashboard
            
            ok "Phase 3: Database provisioning, configuration verification, and health dashboard completed."
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
        "tailscale")
            configure_tailscale
            ;;
        "dashboard")
            print_health_dashboard
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

# --- Tailscale VPN Configuration Function ---
configure_tailscale() {
    [[ -n "${TAILSCALE_AUTH_KEY:-}" ]] || { log "INFO" "TAILSCALE_AUTHKEY not set — skipping"; return 0; }
    
    log "INFO" "Authenticating Tailscale (compose service)..."
    
    cd "${TENANT_DIR}"
    
    # Check if Tailscale service is running
    if ! docker compose ps --filter "name=tailscale" --filter "status=running" | grep -q "tailscale"; then
        log "WARN" "Tailscale service not running, starting it first..."
        docker compose up -d tailscale
        sleep 10
    fi
    
    # Authenticate with Tailscale
    docker compose exec -T tailscale tailscale up \
        --authkey="${TAILSCALE_AUTH_KEY}" \
        --hostname="${TENANT:-ai-platform}" \
        --accept-routes
    
    sleep 5
    
    # Capture Tailscale IP for dashboard
    TAILSCALE_IP=$(docker compose exec -T tailscale tailscale ip -4 2>/dev/null | tr -d ' \n' || echo "")
    if [[ -n "$TAILSCALE_IP" ]]; then
        log "OK" "Tailscale IP: ${TAILSCALE_IP}"
        # Persist for dashboard and future use
        grep -q "^TAILSCALE_IP=" "${ENV_FILE}" && \
            sed -i "s|^TAILSCALE_IP=.*|TAILSCALE_IP=${TAILSCALE_IP}|" "${ENV_FILE}" || \
            echo "TAILSCALE_IP=${TAILSCALE_IP}" >> "${ENV_FILE}"
    else
        log "WARN" "Could not determine Tailscale IP — check: docker compose logs tailscale"
    fi
}

# --- Health Dashboard Function ---
print_health_dashboard() {
    # Reload env to pick up TAILSCALE_IP written during this session
    set -a; source "${ENV_FILE}"; set +a

    echo ""
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║           PLATFORM HEALTH DASHBOARD                 ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
    echo "  Tailscale IP : ${TAILSCALE_IP:-NOT CONNECTED}"
    echo "  Domain       : https://${DOMAIN}"
    echo ""

    check_svc() {
        local name="$1" url="$2"
        if curl -sf --max-time 5 "$url" > /dev/null 2>&1; then
            printf "  %-20s %s\n" "$name" "🟢 OK  $url"
        else
            printf "  %-20s %s\n" "$name" "🔴 FAIL  $url"
        fi
    }

    echo "Core Infrastructure:"
    check_svc "PostgreSQL" "$(docker compose exec -T postgres pg_isready -U "${POSTGRES_USER:-postgres}" -q 2>/dev/null && echo OK)"
    check_svc "Redis" "$(docker compose exec -T redis redis-cli ping 2>/dev/null && echo OK)"
    check_svc "LiteLLM" "http://localhost:${PORT_LITELLM:-4000}/health/liveliness"
    check_svc "Grafana" "http://localhost:${PORT_GRAFANA:-3002}/api/health"
    check_svc "n8n" "http://localhost:${PORT_N8N:-5678}/healthz"
    check_svc "Qdrant" "http://localhost:${PORT_QDRANT:-6333}/collections"
    check_svc "OpenWebUI" "http://localhost:${PORT_OPENWEBUI:-3000}/"
    check_svc "Prometheus" "http://localhost:${PORT_PROMETHEUS:-9090}/-/healthy"

    echo ""
    echo "Service Access URLs:"
    if [[ -n "${DOMAIN:-}" ]]; then
        check_svc "Main Domain" "https://${DOMAIN}"
        check_svc "Grafana" "https://grafana.${DOMAIN}"
        check_svc "n8n" "https://n8n.${DOMAIN}"
        check_svc "OpenWebUI" "https://openwebui.${DOMAIN}"
    fi

    echo ""
    echo "Service Tests:"
    echo "  LiteLLM test: curl -s http://localhost:${PORT_LITELLM:-4000}/v1/models \\"
    echo "              -H 'Authorization: Bearer \${LITELLM_MASTER_KEY}'"
    echo "  OpenClaw test: curl -s http://localhost:${PORT_OPENCLAW:-8080}/signal"
    echo ""
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

# ─── Phase 3: Database Provisioning and Verification ───────────────────────────
provision_databases() {
    log "INFO" "Starting Phase 3: Database Provisioning and Verification"
    
    # PostgreSQL provisioning
    if [[ "${ENABLE_POSTGRES}" == "true" ]]; then
        provision_postgresql_database
    fi
    
    # Redis provisioning
    if [[ "${ENABLE_REDIS}" == "true" ]]; then
        provision_redis_cache
    fi
    
    # Vector database provisioning
    if [[ "${ENABLE_QDRANT}" == "true" ]]; then
        provision_qdrant_vector_db
    fi
    
    ok "Database provisioning completed"
}

provision_postgresql_database() {
    log "INFO" "Provisioning PostgreSQL database..."
    
    # Wait for PostgreSQL to be ready
    local max_wait=30
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        if docker exec "ai-${TENANT_ID}-postgres-1" pg_isready -U postgres &>/dev/null; then
            break
        fi
        sleep 2
        wait_time=$((wait_time + 2))
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        fail "PostgreSQL did not become ready within ${max_wait} seconds"
    fi
    
    # Create application databases
    local databases=("n8n" "grafana" "openwebui" "anythingllm")
    
    for db in "${databases[@]}"; do
        # Check if service is enabled
        if [[ $(declare -p "ENABLE_${db^^}" 2>/dev/null 2>&1) =~ "true" ]]; then
            log "INFO" "Creating database: ${db}"
            
            # Create database if it doesn't exist
            docker exec "ai-${TENANT_ID}-postgres-1" psql -U postgres -tc \
                "SELECT 1 FROM pg_database WHERE datname = '${db}'" | grep -q 1 || \
            docker exec "ai-${TENANT_ID}-postgres-1" psql -U postgres -c \
                "CREATE DATABASE ${db};" &>/dev/null
            
            # Create user and grant permissions
            docker exec "ai-${TENANT_ID}-postgres-1" psql -U postgres -tc \
                "SELECT 1 FROM pg_roles WHERE rolname = '${db}_user'" | grep -q 1 || \
            docker exec "ai-${TENANT_ID}-postgres-1" psql -U postgres -c \
                "CREATE USER ${db}_user WITH PASSWORD '${POSTGRES_PASSWORD}';" &>/dev/null
            
            docker exec "ai-${TENANT_ID}-postgres-1" psql -U postgres -c \
                "GRANT ALL PRIVILEGES ON DATABASE ${db} TO ${db}_user;" &>/dev/null
            
            ok "Database ${db} created and configured"
        fi
    done
    
    # Verify database connectivity
    verify_postgresql_connectivity
}

provision_redis_cache() {
    log "INFO" "Provisioning Redis cache..."
    
    # Wait for Redis to be ready
    local max_wait=30
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        if docker exec "ai-${TENANT_ID}-redis-1" redis-cli ping &>/dev/null; then
            break
        fi
        sleep 2
        wait_time=$((wait_time + 2))
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        fail "Redis did not become ready within ${max_wait} seconds"
    fi
    
    # Configure Redis settings
    docker exec "ai-${TENANT_ID}-redis-1" redis-cli CONFIG SET maxmemory 256mb &>/dev/null
    docker exec "ai-${TENANT_ID}-redis-1" redis-cli CONFIG SET maxmemory-policy allkeys-lru &>/dev/null
    
    # Test Redis functionality
    docker exec "ai-${TENANT_ID}-redis-1" redis-cli SET test_key "test_value" &>/dev/null
    local test_value=$(docker exec "ai-${TENANT_ID}-redis-1" redis-cli GET test_key 2>/dev/null)
    
    if [[ "$test_value" == "test_value" ]]; then
        docker exec "ai-${TENANT_ID}-redis-1" redis-cli DEL test_key &>/dev/null
        ok "Redis cache provisioned and verified"
    else
        fail "Redis functionality test failed"
    fi
}

provision_qdrant_vector_db() {
    log "INFO" "Provisioning Qdrant vector database..."
    
    # Wait for Qdrant to be ready
    local max_wait=30
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        if curl -s -f "http://localhost:6333/collections" &>/dev/null; then
            break
        fi
        sleep 2
        wait_time=$((wait_time + 2))
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        fail "Qdrant did not become ready within ${max_wait} seconds"
    fi
    
    # Create collections for AI services
    local collections=("openwebui_embeddings" "n8n_embeddings" "documents")
    
    for collection in "${collections[@]}"; do
        log "INFO" "Creating collection: ${collection}"
        
        # Check if collection exists
        if ! curl -s -f "http://localhost:6333/collections/${collection}" &>/dev/null; then
            # Create collection with default configuration
            curl -s -X PUT "http://localhost:6333/collections/${collection}" \
                -H "Content-Type: application/json" \
                -d '{
                    "vectors": {
                        "size": 1536,
                        "distance": "Cosine"
                    }
                }' &>/dev/null
            
            ok "Collection ${collection} created"
        else
            log "INFO" "Collection ${collection} already exists"
        fi
    done
    
    # Verify Qdrant functionality
    verify_qdrant_functionality
}

verify_postgresql_connectivity() {
    log "INFO" "Verifying PostgreSQL connectivity..."
    
    local databases=("n8n" "grafana" "openwebui" "anythingllm")
    
    for db in "${databases[@]}"; do
        if [[ $(declare -p "ENABLE_${db^^}" 2>/dev/null 2>&1) =~ "true" ]]; then
            # Test database connection
            if docker exec "ai-${TENANT_ID}-postgres-1" psql -U "${db}_user" -d "${db}" -c "SELECT 1;" &>/dev/null; then
                ok "PostgreSQL ${db} database connectivity verified"
            else
                fail "PostgreSQL ${db} database connectivity failed"
            fi
        fi
    done
}

verify_qdrant_functionality() {
    log "INFO" "Verifying Qdrant functionality..."
    
    # Test collection creation and vector operations
    local test_collection="test_collection"
    
    # Create test collection
    curl -s -X PUT "http://localhost:6333/collections/${test_collection}" \
        -H "Content-Type: application/json" \
        -d '{
            "vectors": {
                "size": 1536,
                "distance": "Cosine"
            }
        }' &>/dev/null
    
    # Add test vector
    curl -s -X PUT "http://localhost:6333/collections/${test_collection}/points" \
        -H "Content-Type: application/json" \
        -H "api-key: ${QDRANT_API_KEY}" \
        -d '{
            "points": [
                {
                    "id": 1,
                    "vector": [0.1, 0.2, 0.3],
                    "payload": {"test": "data"}
                }
            ]
        }' &>/dev/null
    
    # Search test vector
    local search_result=$(curl -s -X POST "http://localhost:6333/collections/${test_collection}/search" \
        -H "Content-Type: application/json" \
        -H "api-key: ${QDRANT_API_KEY}" \
        -d '{
            "vector": [0.1, 0.2, 0.3],
            "limit": 1
        }' | jq -r '.result | length' 2>/dev/null)
    
    if [[ "$search_result" == "1" ]]; then
        # Cleanup test collection
        curl -s -X DELETE "http://localhost:6333/collections/${test_collection}" &>/dev/null
        ok "Qdrant functionality verified"
    else
        fail "Qdrant functionality test failed"
    fi
}

# ─── Configuration Verification ─────────────────────────────────────────────
verify_service_configurations() {
    log "INFO" "Verifying service configurations..."
    
    # Verify environment variables
    verify_environment_variables
    
    # Verify service connections
    verify_service_connections
    
    # Verify data persistence
    verify_data_persistence
    
    ok "Service configuration verification completed"
}

verify_environment_variables() {
    log "INFO" "Verifying critical environment variables..."
    
    local critical_vars=(
        "POSTGRES_PASSWORD"
        "REDIS_PASSWORD"
        "QDRANT_API_KEY"
        "TENANT_UID"
        "TENANT_GID"
        "DOCKER_NETWORK"
    )
    
    for var in "${critical_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            ok "Environment variable ${var} is set"
        else
            warn "Environment variable ${var} is not set"
        fi
    done
}

verify_service_connections() {
    log "INFO" "Verifying service-to-service connections..."
    
    # Test Grafana to Prometheus connection
    if [[ "${ENABLE_GRAFANA}" == "true" && "${ENABLE_PROMETHEUS}" == "true" ]]; then
        if curl -s -f "http://localhost:3000/api/health" &>/dev/null; then
            ok "Grafana service is accessible"
        else
            warn "Grafana service is not accessible"
        fi
    fi
    
    # Test OpenWebUI to Ollama connection
    if [[ "${ENABLE_OPENWEBUI}" == "true" && "${ENABLE_OLLAMA}" == "true" ]]; then
        if curl -s -f "http://localhost:8080" &>/dev/null; then
            ok "OpenWebUI service is accessible"
        else
            warn "OpenWebUI service is not accessible"
        fi
    fi
}

verify_data_persistence() {
    log "INFO" "Verifying data persistence..."
    
    # Check if data directories exist and have correct permissions
    local data_dirs=("postgres" "redis" "qdrant" "grafana" "prometheus")
    
    for dir in "${data_dirs[@]}"; do
        if [[ $(declare -p "ENABLE_${dir^^}" 2>/dev/null 2>&1) =~ "true" ]]; then
            local service_path="${TENANT_DIR}/${dir}"
            if [[ -d "$service_path" ]]; then
                ok "Data directory ${dir} exists"
            else
                warn "Data directory ${dir} does not exist"
            fi
        fi
    done
}

# ─── Service Log Configuration Functions ─────────────────────────────────────
# These functions are the central engine for all complex configuration generation
# They are exported to be used by other scripts in the deployment pipeline

# Dynamic Caddyfile Generator
generate_caddyfile() {
    # --- PATH CORRECTION ---
    # Define the correct, final path including the 'caddy' subdirectory.
    local CADDY_FILE_PATH="${TENANT_DIR}/caddy/Caddyfile"
    log "INFO" "Generating Caddyfile at: ${CADDY_FILE_PATH}"
    
    # Ensure caddy directory exists
    mkdir -p "$(dirname "${CADDY_FILE_PATH}")"
    
    # Generate Caddyfile with all service routes
    cat > "${CADDY_FILE_PATH}" << 'EOF'
{
    email {$ADMIN_EMAIL}
    auto_https {
        on
    }
    fi

    if [[ "${ENABLE_ANYTHINGLLM}" == "true" ]]; then
        cat >> "$TMP_CADDY" << EOF
anythingllm.${DOMAIN} {
    reverse_proxy anythingllm:3001
}
EOF
        ok "Caddy route added for AnythingLLM."
    fi

    if [[ "${ENABLE_LITELLM}" == "true" ]]; then
        cat >> "$TMP_CADDY" << EOF
litellm.${DOMAIN} {
    reverse_proxy litellm:4000
}
EOF
        ok "Caddy route added for LiteLLM."
    fi

    if [[ "${ENABLE_DIFY}" == "true" ]]; then
        cat >> "$TMP_CADDY" << EOF
${DOMAIN}/dify {
    reverse_proxy dify:3001
}
EOF
        ok "Caddy route added for Dify."
    fi

    if [[ "${ENABLE_SIGNAL}" == "true" ]]; then
        cat >> "$TMP_CADDY" << EOF
${DOMAIN}/signal {
    reverse_proxy signal:8080
}
EOF
        ok "Caddy route added for Signal."
    fi

    if [[ "${ENABLE_OPENCLAW}" == "true" ]]; then
        cat >> "$TMP_CADDY" << EOF
${DOMAIN}/openclaw {
    reverse_proxy openclaw:8082
}
EOF
        ok "Caddy route added for OpenClaw."
    fi

    # 4. Write the final Caddyfile with proper permissions
    mkdir -p "$(dirname "$CADDY_FILE_PATH")"
    mv "$TMP_CADDY" "$CADDY_FILE_PATH"
    
    # --- OWNERSHIP CORRECTION ---
    # The function now takes responsibility for the file it creates.
    # The 'sudo' is safe if the user running the script has sudo rights.
    # The fix in Script 1 makes this step even more robust.
    chown "${TENANT_UID}:${TENANT_GID}" "$CADDY_FILE_PATH"
    ok "Caddyfile generated and ownership secured."
}

# Dynamic Prometheus Configuration Generator
generate_prometheus_config() {
    local PROMETHEUS_CONFIG_PATH="${TENANT_DIR}/prometheus.yml"
    log "INFO" "Generating Prometheus configuration at: ${PROMETHEUS_CONFIG_PATH}"
    
    cat > "${PROMETHEUS_CONFIG_PATH}" << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'grafana'
    static_configs:
      - targets: ['grafana:3000']
    metrics_path: /api/metrics

  - job_name: 'caddy'
    static_configs:
      - targets: ['caddy:2019']
    metrics_path: /metrics

  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres:5432']
    metrics_path: /metrics

  - job_name: 'redis'
    static_configs:
      - targets: ['redis:6379']
    metrics_path: /metrics

  - job_name: 'qdrant'
    static_configs:
      - targets: ['qdrant:6333']
    metrics_path: /metrics

  - job_name: 'litellm'
    static_configs:
      - targets: ['litellm:4000']
    metrics_path: /metrics

  - job_name: 'openwebui'
    static_configs:
      - targets: ['openwebui:8080']
    metrics_path: /metrics

  - job_name: 'n8n'
    static_configs:
      - targets: ['n8n:5678']
    metrics_path: /metrics

  - job_name: 'flowise'
    static_configs:
      - targets: ['flowise:3000']
    metrics_path: /metrics

  - job_name: 'anythingllm'
    static_configs:
      - targets: ['anythingllm:3001']
    metrics_path: /metrics

  - job_name: 'authentik'
    static_configs:
      - targets: ['authentik-server:9000']
    metrics_path: /metrics

  - job_name: 'signal'
    static_configs:
      - targets: ['signal:8080']
    metrics_path: /metrics

  - job_name: 'openclaw'
    static_configs:
      - targets: ['openclaw:8082']
    metrics_path: /metrics
EOF
    
    ok "Prometheus configuration generated with all service targets."
}

# Export all generator functions for use by other scripts
export -f generate_caddyfile
export -f generate_prometheus_config

# Call main function to execute the script
main "$@"
