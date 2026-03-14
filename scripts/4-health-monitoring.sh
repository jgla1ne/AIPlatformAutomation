#!/usr/bin/env bash
# =============================================================================
# Script 4: Health Monitoring - Comprehensive System Verification
# =============================================================================
# PURPOSE: Phase 4 - Comprehensive health monitoring and system verification
# USAGE:   sudo bash scripts/4-health-monitoring.sh [tenant_id] [action]
# ACTIONS: monitor, dashboard, alerts, verify-all
# =============================================================================

set -euo pipefail

# --- Color Definitions ---
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Logging Functions ---
log() { echo -e "${CYAN}[INFO]${NC}    $1"; }
ok() { echo -e "${GREEN}[OK]${NC}      $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}    $*"; }
fail() { echo -e "${RED}[FAIL]${NC}    $*"; exit 1; }

# --- Tenant Setup ---
if [[ -z "${1:-}" ]]; then
    echo "ERROR: TENANT_ID is required. Usage: sudo bash $0 <tenant_id> [action]" >&2
    exit 1
fi

TENANT_ID="$1"
TENANT_DIR="/mnt/data/${TENANT_ID}"
ENV_FILE="${TENANT_DIR}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
    fail "Environment file not found for tenant '${TENANT_ID}' at ${ENV_FILE}"
fi

log "Loading environment from: ${ENV_FILE}"
set -a
source "${ENV_FILE}" 2>/dev/null || true
set +a

# --- Global Variables ---
ACTION="${2:-monitor}"
HEALTH_LOG="${TENANT_DIR}/logs/health-monitor-$(date +%Y%m%d-%H%M%S).log"
ALERT_LOG="${TENANT_DIR}/logs/health-alerts-$(date +%Y%m%d).log"
METRICS_FILE="${TENANT_DIR}/logs/metrics-$(date +%Y%m%d-%H%M%S).json"

# Ensure log directories exist
mkdir -p "${TENANT_DIR}/logs"

# ─── Phase 4: Comprehensive Health Monitoring ────────────────────────────────
comprehensive_health_monitor() {
    log "Starting Phase 4: Comprehensive Health Monitoring"
    
    # Initialize health monitoring
    initialize_health_monitoring
    
    # Run all health checks
    run_comprehensive_checks
    
    # Generate health report
    generate_health_report
    
    # Check for alerts
    check_health_alerts
    
    ok "Comprehensive health monitoring completed"
}

initialize_health_monitoring() {
    log "Initializing health monitoring system..."
    
    # Create health log with header
    cat > "${HEALTH_LOG}" << EOF
# AI Platform Health Monitoring Report
# Tenant: ${TENANT_ID}
# Timestamp: $(date)
# ========================================

EOF
    
    # Initialize metrics collection
    cat > "${METRICS_FILE}" << EOF
{
  "tenant_id": "${TENANT_ID}",
  "timestamp": "$(date -Iseconds)",
  "checks": {
EOF
    
    log "Health monitoring initialized"
}

run_comprehensive_checks() {
    log "Running comprehensive health checks..."
    
    # System Infrastructure Checks
    check_system_infrastructure
    
    # Container Health Checks
    check_container_health
    
    # Service Connectivity Checks
    check_service_connectivity
    
    # Data Integrity Checks
    check_data_integrity
    
    # Performance Metrics
    collect_performance_metrics
    
    # Security Checks
    check_security_status
    
    log "All comprehensive checks completed"
}

check_system_infrastructure() {
    log "Checking system infrastructure..."
    
    # Docker daemon health
    if docker info &>/dev/null; then
        ok "Docker daemon is healthy"
        echo "  docker_daemon: \"healthy\"," >> "${METRICS_FILE}"
    else
        fail "Docker daemon is not responding"
        echo "  docker_daemon: \"unhealthy\"," >> "${METRICS_FILE}"
    fi
    
    # Disk space check
    local disk_usage=$(df "${TENANT_DIR}" | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $disk_usage -lt 85 ]]; then
        ok "Disk usage is acceptable: ${disk_usage}%"
        echo "  disk_usage: ${disk_usage}," >> "${METRICS_FILE}"
    else
        warn "Disk usage is high: ${disk_usage}%"
        echo "  disk_usage: ${disk_usage}," >> "${METRICS_FILE}"
        log_alert "HIGH_DISK_USAGE" "Disk usage is ${disk_usage}%"
    fi
    
    # Memory check
    local mem_available=$(awk '/MemAvailable/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
    if [[ $mem_available -gt 2 ]]; then
        ok "Available memory: ${mem_available}GB"
        echo "  memory_available_gb: ${mem_available}," >> "${METRICS_FILE}"
    else
        warn "Low memory: ${mem_available}GB available"
        echo "  memory_available_gb: ${mem_available}," >> "${METRICS_FILE}"
        log_alert "LOW_MEMORY" "Only ${mem_available}GB memory available"
    fi
    
    # Network connectivity
    if ping -c 1 8.8.8.8 &>/dev/null; then
        ok "Network connectivity is healthy"
        echo "  network_connectivity: \"healthy\"," >> "${METRICS_FILE}"
    else
        warn "Network connectivity issues detected"
        echo "  network_connectivity: \"unhealthy\"," >> "${METRICS_FILE}"
    fi
}

check_container_health() {
    log "Checking container health..."
    
    cd "${TENANT_DIR}"
    
    # Get all running containers for this tenant
    local containers=$(docker compose ps --format "{{.Name}}" 2>/dev/null || true)
    
    if [[ -z "$containers" ]]; then
        warn "No containers found for tenant ${TENANT_ID}"
        return
    fi
    
    local healthy_count=0
    local total_count=0
    
    while IFS= read -r container; do
        if [[ -n "$container" ]]; then
            total_count=$((total_count + 1))
            
            # Check container health status
            local health_status=$(docker inspect "$container" --format='{{.State.Health.Status}}' 2>/dev/null || echo "none")
            local container_status=$(docker inspect "$container" --format='{{.State.Status}}' 2>/dev/null || echo "unknown")
            
            if [[ "$container_status" == "running" ]]; then
                if [[ "$health_status" == "healthy" || "$health_status" == "none" ]]; then
                    ok "Container $container is healthy"
                    healthy_count=$((healthy_count + 1))
                else
                    warn "Container $container health status: $health_status"
                    log_alert "UNHEALTHY_CONTAINER" "Container $container reports $health_status"
                fi
            else
                fail "Container $container is not running (status: $container_status)"
                log_alert "STOPPED_CONTAINER" "Container $container is not running"
            fi
        fi
    done <<< "$containers"
    
    local health_percentage=$((healthy_count * 100 / total_count))
    echo "  container_health_percentage: ${health_percentage}," >> "${METRICS_FILE}"
    
    log "Container health: $healthy_count/$total_count containers healthy (${health_percentage}%)"
}

check_service_connectivity() {
    log "Checking service connectivity..."
    
    # Define service endpoints to check
    declare -A service_endpoints=(
        ["postgres"]="5432:tcp"
        ["redis"]="6379:tcp"
        ["qdrant"]="6333:http"
        ["grafana"]="3000:http"
        ["prometheus"]="9090:http"
        ["openwebui"]="8080:http"
        ["litellm"]="4000:http"
        ["caddy"]="443:https"
    )
    
    local connectivity_ok=0
    local connectivity_total=0
    
    for service in "${!service_endpoints[@]}"; do
        # Check if service is enabled
        if [[ $(declare -p "ENABLE_${service^^}" 2>/dev/null 2>&1) =~ "true" ]]; then
            connectivity_total=$((connectivity_total + 1))
            
            IFS=':' read -r port protocol <<< "${service_endpoints[$service]}"
            
            case "$protocol" in
                "tcp")
                    if nc -z localhost "$port" &>/dev/null; then
                        ok "Service $service (port $port) is reachable"
                        connectivity_ok=$((connectivity_ok + 1))
                    else
                        warn "Service $service (port $port) is not reachable"
                        log_alert "SERVICE_UNREACHABLE" "Service $service on port $port is not reachable"
                    fi
                    ;;
                "http")
                    if curl -s -f "http://localhost:$port/health" &>/dev/null || \
                       curl -s -f "http://localhost:$port" &>/dev/null; then
                        ok "Service $service (HTTP port $port) is responding"
                        connectivity_ok=$((connectivity_ok + 1))
                    else
                        warn "Service $service (HTTP port $port) is not responding"
                        log_alert "HTTP_SERVICE_DOWN" "HTTP service $service on port $port is not responding"
                    fi
                    ;;
                "https")
                    if curl -k -s -f "https://localhost:$port" &>/dev/null; then
                        ok "Service $service (HTTPS port $port) is responding"
                        connectivity_ok=$((connectivity_ok + 1))
                    else
                        warn "Service $service (HTTPS port $port) is not responding"
                        log_alert "HTTPS_SERVICE_DOWN" "HTTPS service $service on port $port is not responding"
                    fi
                    ;;
            esac
        fi
    done
    
    local connectivity_percentage=$((connectivity_ok * 100 / connectivity_total))
    echo "  service_connectivity_percentage: ${connectivity_percentage}," >> "${METRICS_FILE}"
    
    log "Service connectivity: $connectivity_ok/$connectivity_total services reachable (${connectivity_percentage}%)"
}

check_data_integrity() {
    log "Checking data integrity..."
    
    # Check PostgreSQL databases
    if [[ "${ENABLE_POSTGRES}" == "true" ]]; then
        local databases=("n8n" "grafana" "openwebui" "anythingllm")
        
        for db in "${databases[@]}"; do
            if [[ $(declare -p "ENABLE_${db^^}" 2>/dev/null 2>&1) =~ "true" ]]; then
                if docker exec "ai-${TENANT_ID}-postgres-1" psql -U "${db}_user" -d "$db" -c "SELECT 1;" &>/dev/null; then
                    ok "PostgreSQL database $db is accessible"
                else
                    warn "PostgreSQL database $db is not accessible"
                    log_alert "DATABASE_INACCESSIBLE" "PostgreSQL database $db is not accessible"
                fi
            fi
        done
    fi
    
    # Check Redis data
    if [[ "${ENABLE_REDIS}" == "true" ]]; then
        if docker exec "ai-${TENANT_ID}-redis-1" redis-cli ping &>/dev/null; then
            ok "Redis cache is responsive"
        else
            warn "Redis cache is not responsive"
            log_alert "REDIS_DOWN" "Redis cache is not responding"
        fi
    fi
    
    # Check Qdrant collections
    if [[ "${ENABLE_QDRANT}" == "true" ]]; then
        local collections=("openwebui_embeddings" "n8n_embeddings" "documents")
        
        for collection in "${collections[@]}"; do
            if curl -s -f "http://localhost:6333/collections/$collection" &>/dev/null; then
                ok "Qdrant collection $collection exists"
            else
                warn "Qdrant collection $collection is missing"
                log_alert "COLLECTION_MISSING" "Qdrant collection $collection is missing"
            fi
        done
    fi
}

collect_performance_metrics() {
    log "Collecting performance metrics..."
    
    # Container resource usage
    cd "${TENANT_DIR}"
    
    local containers=$(docker compose ps --format "{{.Name}}" 2>/dev/null || true)
    
    while IFS= read -r container; do
        if [[ -n "$container" ]]; then
            # Get CPU and memory usage
            local stats=$(docker stats "$container" --no-stream --format "table {{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | tail -n1 || echo "0%\t0B / 0B")
            
            echo "    \"${container}\": {" >> "${METRICS_FILE}"
            echo "      \"cpu_usage\": \"$(echo "$stats" | awk '{print $1}')\"," >> "${METRICS_FILE}"
            echo "      \"memory_usage\": \"$(echo "$stats" | awk '{print $2}')\"" >> "${METRICS_FILE}"
            echo "    }," >> "${METRICS_FILE}"
        fi
    done <<< "$containers"
    
    # System load
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    echo "  system_load_average: ${load_avg}," >> "${METRICS_FILE}"
    
    log "Performance metrics collected"
}

check_security_status() {
    log "Checking security status..."
    
    # Check for exposed ports
    local exposed_ports=$(docker ps --format "{{.Ports}}" | grep -c "0.0.0.0" || echo "0")
    echo "  exposed_ports_count: ${exposed_ports}," >> "${METRICS_FILE}"
    
    if [[ $exposed_ports -gt 5 ]]; then
        warn "High number of exposed ports: $exposed_ports"
        log_alert "MANY_EXPOSED_PORTS" "Many ports ($exposed_ports) are exposed to the internet"
    fi
    
    # Check container security (running as root)
    local root_containers=$(docker ps --format "{{.Names}}" | xargs -I {} docker inspect {} --format "{{.HostConfig.Privileged}}" | grep -c "true" || echo "0")
    echo "  privileged_containers: ${root_containers}," >> "${METRICS_FILE}"
    
    if [[ $root_containers -gt 0 ]]; then
        warn "Found $root_containers privileged containers"
        log_alert "PRIVILEGED_CONTAINERS" "Found $root_containers privileged containers"
    fi
    
    log "Security status check completed"
}

generate_health_report() {
    log "Generating comprehensive health report..."
    
    # Close the metrics JSON
    echo "  }," >> "${METRICS_FILE}"
    echo "  \"timestamp\": \"$(date -Iseconds)\"" >> "${METRICS_FILE}"
    echo "}" >> "${METRICS_FILE}"
    
    # Generate human-readable report
    cat >> "${HEALTH_LOG}" << EOF

# Health Summary
# Generated: $(date)
# ========================================

System Overview:
- Tenant: ${TENANT_ID}
- Total Services: $(docker compose ps --format "{{.Name}}" 2>/dev/null | wc -l)
- Health Check Timestamp: $(date)

Detailed Metrics:
$(cat "${METRICS_FILE}" | jq -r 'to_entries[] | "  \(.key): \(.value)"' 2>/dev/null || echo "  Metrics available in JSON format")

Recommendations:
- Review any WARN or FAIL messages above
- Check alerts log: ${ALERT_LOG}
- Monitor metrics file: ${METRICS_FILE}

EOF
    
    ok "Health report generated: ${HEALTH_LOG}"
}

check_health_alerts() {
    log "Checking for health alerts..."
    
    if [[ -f "${ALERT_LOG}" ]] && [[ -s "${ALERT_LOG}" ]]; then
        local alert_count=$(wc -l < "${ALERT_LOG}")
        if [[ $alert_count -gt 0 ]]; then
            warn "Found $alert_count health alerts"
            log "Recent alerts:"
            tail -10 "${ALERT_LOG}" | while read -r line; do
                echo "  $line"
            done
        fi
    else
        ok "No health alerts found"
    fi
}

log_alert() {
    local alert_type="$1"
    local message="$2"
    local timestamp=$(date -Iseconds)
    
    echo "${timestamp} [${alert_type}] ${message}" >> "${ALERT_LOG}"
    
    # Also log to console
    warn "ALERT: ${alert_type} - ${message}"
}

show_health_dashboard() {
    log "Displaying health monitoring dashboard..."
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    AI PLATFORM HEALTH DASHBOARD                  ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # System Overview
    echo "📊 SYSTEM OVERVIEW"
    echo "├── Tenant: ${TENANT_ID}"
    echo "├── Timestamp: $(date)"
    echo "└── Data Directory: ${TENANT_DIR}"
    echo ""
    
    # Container Status
    echo "🐳 CONTAINER STATUS"
    cd "${TENANT_DIR}"
    docker compose ps 2>/dev/null || echo "No containers found"
    echo ""
    
    # Resource Usage
    echo "💾 RESOURCE USAGE"
    echo "├── Disk Usage: $(df "${TENANT_DIR}" | awk 'NR==2 {print $5}')"
    echo "├── Available Memory: $(awk '/MemAvailable/ {printf "%.1fGB", $2/1024/1024}' /proc/meminfo)"
    echo "└── System Load: $(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')"
    echo ""
    
    # Service Connectivity
    echo "🔗 SERVICE CONNECTIVITY"
    declare -A service_ports=(
        ["PostgreSQL"]="5432"
        ["Redis"]="6379"
        ["Qdrant"]="6333"
        ["Grafana"]="3000"
        ["Prometheus"]="9090"
        ["OpenWebUI"]="8080"
        ["LiteLLM"]="4000"
        ["Caddy"]="443"
    )
    
    for service in "${!service_ports[@]}"; do
        local port="${service_ports[$service]}"
        if nc -z localhost "$port" &>/dev/null; then
            echo "├── ✅ $service (port $port)"
        else
            echo "├── ❌ $service (port $port)"
        fi
    done
    echo "└── Health Check Complete"
    echo ""
    
    # Recent Alerts
    if [[ -f "${ALERT_LOG}" ]] && [[ -s "${ALERT_LOG}" ]]; then
        echo "🚨 RECENT ALERTS"
        tail -5 "${ALERT_LOG}" | while read -r line; do
            echo "├── $line"
        done
        echo "└── End of alerts"
    else
        echo "🚨 RECENT ALERTS"
        echo "└── No alerts found"
    fi
    echo ""
}

# ─── Main Function ─────────────────────────────────────────────────────────────
main() {
    case "$ACTION" in
        "monitor")
            comprehensive_health_monitor
            ;;
        "dashboard")
            show_health_dashboard
            ;;
        "verify-all")
            log "Running complete system verification..."
            comprehensive_health_monitor
            show_health_dashboard
            ;;
        "alerts")
            if [[ -f "${ALERT_LOG}" ]] && [[ -s "${ALERT_LOG}" ]]; then
                echo "Health Alerts Log:"
                cat "${ALERT_LOG}"
            else
                echo "No health alerts found."
            fi
            ;;
        *)
            echo "Usage: sudo bash $0 <tenant_id> [action]"
            echo ""
            echo "Actions:"
            echo "  monitor    - Run comprehensive health monitoring"
            echo "  dashboard  - Show health monitoring dashboard"
            echo "  verify-all - Run complete system verification with dashboard"
            echo "  alerts     - Show health alerts log"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"
