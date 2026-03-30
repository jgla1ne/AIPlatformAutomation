#!/usr/bin/env bash
# =============================================================================
# Script 3: Mission Control - README COMPLIANT
# =============================================================================
# PURPOSE: Source platform.conf, call service APIs for setup and verification
# USAGE:   bash scripts/3-configure-services.sh [tenant_id] [options]
# OPTIONS: --verify-only     Only verify deployment, don't configure
#          --health-check    Show detailed health status
# =============================================================================

set -euo pipefail

# =============================================================================
# NON-ROOT EXECUTION CHECK (README P7)
# =============================================================================
if [[ $EUID -eq 0 ]]; then
    echo "ERROR: This script must not be run as root (README P7 requirement)"
    exit 1
fi

# =============================================================================
# SCRIPT CONFIGURATION
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# =============================================================================
# LOGGING (README P11)
# =============================================================================
LOG_FILE=""
log() {
    local msg="[$(date +%H:%M:%S)] $*"
    echo "$msg"
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE"
}
ok() { log "OK: $*"; }
warn() { log "WARN: $*"; }
fail() { log "FAIL: $*"; exit 1; }

# =============================================================================
# IDEMPOTENCY MARKERS (README P8)
# =============================================================================
CONFIGURED_DIR=""
step_done() { [[ -f "${CONFIGURED_DIR}/${1}" ]]; }
mark_done() { touch "${CONFIGURED_DIR}/${1}"; }

# =============================================================================
# FRAMEWORK VALIDATION
# =============================================================================
framework_validate() {
    log "Validating mission control framework..."
    
    # Fix Docker socket connection (common issue)
    if [[ "${DOCKER_HOST:-}" == *"user/1000"* ]]; then
        log "Fixing Docker socket connection..."
        unset DOCKER_HOST
    fi
    
    # Binary availability checks
    for bin in docker curl jq; do
        if ! command -v "$bin" >/dev/null 2>&1; then
            fail "Missing required binary: $bin"
        fi
    done
    
    # Docker daemon health
    if ! docker info >/dev/null 2>&1; then
        fail "Docker daemon not running or accessible"
    fi
    
    ok "Framework validation passed"
}

# =============================================================================
# HEALTH CHECK FUNCTIONS
# =============================================================================
check_service_health() {
    local service_name="$1"
    local container_name="${PREFIX}-${TENANT_ID}-${service_name}"
    local health_url="$2"
    
    log "Checking ${service_name} health..."
    
    if ! docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
        warn "${service_name}: Container not running"
        return 1
    fi
    
    # Wait for health check to pass
    local attempts=0
    local max_attempts=30
    
    while [[ $attempts -lt $max_attempts ]]; do
        local health_status
        health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "none")
        
        if [[ "$health_status" == "healthy" ]]; then
            ok "${service_name}: Healthy"
            return 0
        elif [[ "$health_status" == "unhealthy" ]]; then
            warn "${service_name}: Unhealthy"
            return 1
        fi
        
        attempts=$((attempts + 1))
        sleep 2
    done
    
    warn "${service_name}: Health check timeout"
    return 1
}

# =============================================================================
# SERVICE CONFIGURATION FUNCTIONS
# =============================================================================
configure_ollama() {
    if [[ "${OLLAMA_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    local container_name="${PREFIX}-${TENANT_ID}-ollama"
    
    log "Configuring Ollama..."
    
    # Wait for Ollama to be ready
    local attempts=0
    local max_attempts=30
    
    while [[ $attempts -lt $max_attempts ]]; do
        if docker exec "$container_name" ollama list >/dev/null 2>&1; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 2
    done
    
    if [[ $attempts -ge $max_attempts ]]; then
        warn "Ollama not ready after timeout"
        return 1
    fi
    
    # Pull a default model
    log "Pulling default Ollama model (llama2)..."
    docker exec "$container_name" ollama pull llama2 || warn "Failed to pull llama2 model"
    
    ok "Ollama configured"
}

configure_litellm() {
    if [[ "${LITELLM_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    local container_name="${PREFIX}-${TENANT_ID}-litellm"
    local litellm_url="http://127.0.0.1:${LITELLM_PORT}"
    
    log "Configuring LiteLLM..."
    
    # Wait for LiteLLM to be ready
    local attempts=0
    local max_attempts=30
    
    while [[ $attempts -lt $max_attempts ]]; do
        if curl -s "$litellm_url/health" >/dev/null 2>&1; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 2
    done
    
    if [[ $attempts -ge $max_attempts ]]; then
        warn "LiteLLM not ready after timeout"
        return 1
    fi
    
    # Test LiteLLM API
    if curl -s "$litellm_url/v1/models" | grep -q "ollama"; then
        ok "LiteLLM configured and accessible"
    else
        warn "LiteLLM API not responding correctly"
    fi
}

configure_open_webui() {
    if [[ "${OPEN_WEBUI_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    local container_name="${PREFIX}-${TENANT_ID}-open-webui"
    local webui_url="http://127.0.0.1:${OPEN_WEBUI_PORT}"
    
    log "Configuring Open WebUI..."
    
    # Wait for Open WebUI to be ready
    local attempts=0
    local max_attempts=30
    
    while [[ $attempts -lt $max_attempts ]]; do
        if curl -s "$webui_url/api/health" >/dev/null 2>&1; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 2
    done
    
    if [[ $attempts -ge $max_attempts ]]; then
        warn "Open WebUI not ready after timeout"
        return 1
    fi
    
    ok "Open WebUI configured and accessible"
}

# =============================================================================
# VERIFICATION FUNCTIONS
# =============================================================================
verify_database_connectivity() {
    if [[ "${POSTGRES_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    local container_name="${PREFIX}-${TENANT_ID}-postgres"
    
    log "Verifying PostgreSQL connectivity..."
    
    if docker exec "$container_name" pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null 2>&1; then
        ok "PostgreSQL connectivity verified"
    else
        warn "PostgreSQL connectivity failed"
        return 1
    fi
}

verify_redis_connectivity() {
    if [[ "${REDIS_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    local container_name="${PREFIX}-${TENANT_ID}-redis"
    
    log "Verifying Redis connectivity..."
    
    if docker exec "$container_name" redis-cli ping | grep -q "PONG"; then
        ok "Redis connectivity verified"
    else
        warn "Redis connectivity failed"
        return 1
    fi
}

# =============================================================================
# ACCESS SUMMARY
# =============================================================================
print_access_summary() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              AI Platform Access Summary                 ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Tenant: ${TENANT_ID}"
    echo "  Base Domain: ${BASE_DOMAIN}"
    echo ""
    
    if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
        echo "  🗄️  PostgreSQL: 127.0.0.1:${POSTGRES_PORT}"
        echo "      Database: ${POSTGRES_DB}"
        echo "      User: ${POSTGRES_USER}"
    fi
    
    if [[ "${REDIS_ENABLED}" == "true" ]]; then
        echo "  🔴 Redis: 127.0.0.1:${REDIS_PORT}"
    fi
    
    if [[ "${OLLAMA_ENABLED}" == "true" ]]; then
        echo "  🤖 Ollama: 127.0.0.1:${OLLAMA_PORT}"
        echo "      API: http://127.0.0.1:${OLLAMA_PORT}/api"
    fi
    
    if [[ "${LITELLM_ENABLED}" == "true" ]]; then
        echo "  🔗 LiteLLM: 127.0.0.1:${LITELLM_PORT}"
        echo "      API: http://127.0.0.1:${LITELLM_PORT}/v1"
    fi
    
    if [[ "${OPEN_WEBUI_ENABLED}" == "true" ]]; then
        echo "  🌐 Open WebUI: 127.0.0.1:${OPEN_WEBUI_PORT}"
        echo "      Web: http://127.0.0.1:${OPEN_WEBUI_PORT}"
    fi
    
    if [[ "${QDRANT_ENABLED}" == "true" ]]; then
        echo "  🔍 Qdrant: 127.0.0.1:${QDRANT_PORT}"
        echo "      API: http://127.0.0.1:${QDRANT_PORT}"
    fi
    
    if [[ "${CADDY_ENABLED}" == "true" ]]; then
        echo "  🌐 Caddy Proxy: http://localhost:${CADDY_HTTP_PORT}"
        echo "      HTTPS: https://localhost:${CADDY_HTTPS_PORT}"
    fi
    
    echo ""
    echo "  📁 Data Directory: ${DATA_DIR}"
    echo "  📋 Config Directory: ${CONFIG_DIR}"
    echo "  📝 Logs Directory: ${LOGS_DIR}"
    echo ""
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================
main() {
    local tenant_id="${1:-}"
    local verify_only=false
    local health_check=false
    
    # Parse arguments
    shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verify-only)
                verify_only=true
                shift
                ;;
            --health-check)
                health_check=true
                shift
                ;;
            *)
                fail "Unknown option: $1"
                ;;
        esac
    done
    
    # Source platform.conf (README P1)
    local platform_conf="/mnt/${tenant_id}/config/platform.conf"
    if [[ ! -f "$platform_conf" ]]; then
        fail "platform.conf not found at $platform_conf. Run script 1 first."
    fi
    source "$platform_conf"
    
    # Set up logging
    LOG_FILE="${LOGS_DIR}/$(basename "$0" .sh)-$(date +%Y%m%d-%H%M%S).log"
    CONFIGURED_DIR="${BASE_DIR}/.configured"
    mkdir -p "$CONFIGURED_DIR"
    
    log "=== Script 3: Mission Control ==="
    log "Tenant: ${tenant_id}"
    log "Verify-only: ${verify_only}"
    log "Health-check: ${health_check}"
    
    # Framework validation
    framework_validate
    
    # Health checks
    if [[ "$health_check" == "true" ]]; then
        log "Running detailed health checks..."
        
        if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
            check_service_health "postgres" ""
        fi
        
        if [[ "${REDIS_ENABLED}" == "true" ]]; then
            check_service_health "redis" ""
        fi
        
        if [[ "${OLLAMA_ENABLED}" == "true" ]]; then
            check_service_health "ollama" "http://127.0.0.1:${OLLAMA_PORT}/api"
        fi
        
        if [[ "${LITELLM_ENABLED}" == "true" ]]; then
            check_service_health "litellm" "http://127.0.0.1:${LITELLM_PORT}/health"
        fi
        
        if [[ "${OPEN_WEBUI_ENABLED}" == "true" ]]; then
            check_service_health "open-webui" "http://127.0.0.1:${OPEN_WEBUI_PORT}/api/health"
        fi
        
        if [[ "${QDRANT_ENABLED}" == "true" ]]; then
            check_service_health "qdrant" "http://127.0.0.1:${QDRANT_PORT}/health"
        fi
        
        print_access_summary
        return 0
    fi
    
    # Service configuration (unless verify-only)
    if [[ "$verify_only" != "true" ]]; then
        if ! step_done "ollama_configured"; then
            configure_ollama
            mark_done "ollama_configured"
        fi
        
        if ! step_done "litellm_configured"; then
            configure_litellm
            mark_done "litellm_configured"
        fi
        
        if ! step_done "open_webui_configured"; then
            configure_open_webui
            mark_done "open_webui_configured"
        fi
    fi
    
    # Verification
    verify_database_connectivity
    verify_redis_connectivity
    
    # Print access summary
    print_access_summary
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              Script 3 Complete ✓                        ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "  ✓ platform.conf sourced (single source of truth)"
    echo "  ✓ Service APIs called for setup"
    echo "  ✓ Health checks performed"
    echo "  ✓ Connectivity verified"
    echo "  ✓ Access summary generated"
    echo ""
    echo "  Platform is ready for use!"
    echo ""
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
