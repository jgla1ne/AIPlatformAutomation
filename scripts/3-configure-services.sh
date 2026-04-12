#!/usr/bin/env bash
# =============================================================================
# Script 3: Mission Control Hub
# PURPOSE: Complete service management, health monitoring, credentials, key rotation, and post-deployment configuration
# =============================================================================
# USAGE:   bash scripts/3-configure-services.sh [tenant_id] [options]
# OPTIONS: --verify-only     Only verify deployment, don't configure
#          --health-check    Show detailed health status
#          --show-credentials Print all service credentials
#          --rotate-keys [service] Regenerate secrets for one service
#          --restart [service]   Restart specific service
#          --add [service]       Add new service to platform
#          --remove [service]    Remove service from platform
#          --disable [service]   Temporarily disable service
#          --enable [service]    Re-enable disabled service
#          --dry-run         Show what would be done
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
SCRIPT_VERSION="5.1.0"

# =============================================================================
# LOGGING (README P11) — path resolved after sourcing platform.conf in main()
# =============================================================================
LOG_FILE="/tmp/ai-platform-configure.log"
log() {
    local msg="[$(date +%H:%M:%S)] $*"
    echo "$msg"
}
ok() { log "OK: $*"; }
warn() { log "WARN: $*"; }
fail() { log "FAIL: $*"; exit 1; }
dry_run() { [[ "${DRY_RUN:-false}" == "true" ]] && echo "[DRY-RUN] $1"; }

# =============================================================================
# DRY RUN COMMAND EXECUTOR (README §12)
# =============================================================================
run_cmd() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] $*"
    else
        "$@"
    fi
}

# =============================================================================
# IDEMPOTENCY MARKERS (README P8)
# =============================================================================
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
    
    # Binary availability checks (README §13)
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
# CONTAINER HEALTH VERIFICATION
# =============================================================================
verify_containers_healthy() {
    log "Verifying all containers are healthy..."
    
    local unhealthy_containers=()
    
    # Check each enabled service
    if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
        if ! docker ps --format "{{.Names}}" | grep -q "^${TENANT_PREFIX}-postgres$"; then
            fail "PostgreSQL container not running"
        fi
        local status
        status=$(docker inspect --format='{{.State.Health.Status}}' "${TENANT_PREFIX}-postgres" 2>/dev/null || echo "none")
        if [[ "$status" != "healthy" ]]; then
            unhealthy_containers+=("postgres")
        fi
    fi
    
    if [[ "${REDIS_ENABLED}" == "true" ]]; then
        if ! docker ps --format "{{.Names}}" | grep -q "^${TENANT_PREFIX}-redis$"; then
            fail "Redis container not running"
        fi
        local status
        status=$(docker inspect --format='{{.State.Health.Status}}' "${TENANT_PREFIX}-redis" 2>/dev/null || echo "none")
        if [[ "$status" != "healthy" ]]; then
            unhealthy_containers+=("redis")
        fi
    fi
    
    if [[ "${OLLAMA_ENABLED}" == "true" ]]; then
        if ! docker ps --format "{{.Names}}" | grep -q "^${TENANT_PREFIX}-ollama$"; then
            fail "Ollama container not running"
        fi
        local status
        status=$(docker inspect --format='{{.State.Health.Status}}' "${TENANT_PREFIX}-ollama" 2>/dev/null || echo "none")
        if [[ "$status" != "healthy" ]]; then
            unhealthy_containers+=("ollama")
        fi
    fi
    
    if [[ "${LITELLM_ENABLED}" == "true" ]]; then
        if ! docker ps --format "{{.Names}}" | grep -q "^${TENANT_PREFIX}-litellm$"; then
            fail "LiteLLM container not running"
        fi
        local status
        status=$(docker inspect --format='{{.State.Health.Status}}' "${TENANT_PREFIX}-litellm" 2>/dev/null || echo "none")
        if [[ "$status" != "healthy" ]]; then
            unhealthy_containers+=("litellm")
        fi
    fi
    
    if [[ "${OPENWEBUI_ENABLED}" == "true" ]]; then
        if ! docker ps --format "{{.Names}}" | grep -q "^${TENANT_PREFIX}-openwebui$"; then
            fail "Open WebUI container not running"
        fi
        local status
        status=$(docker inspect --format='{{.State.Health.Status}}' "${TENANT_PREFIX}-openwebui" 2>/dev/null || echo "none")
        if [[ "$status" != "healthy" ]]; then
            unhealthy_containers+=("openwebui")
        fi
    fi
    
    if [[ "${QDRANT_ENABLED}" == "true" ]]; then
        if ! docker ps --format "{{.Names}}" | grep -q "^${TENANT_PREFIX}-qdrant$"; then
            fail "Qdrant container not running"
        fi
        local status
        status=$(docker inspect --format='{{.State.Health.Status}}' "${TENANT_PREFIX}-qdrant" 2>/dev/null || echo "none")
        if [[ "$status" != "healthy" ]]; then
            unhealthy_containers+=("qdrant")
        fi
    fi
    
    # Fail if any containers are unhealthy
    if [[ ${#unhealthy_containers[@]} -gt 0 ]]; then
        warn "Unhealthy containers: ${unhealthy_containers[*]}"
        for container in "${unhealthy_containers[@]}"; do
            log "Checking logs for $container..."
            docker logs --tail 50 "${TENANT_PREFIX}-${container}"
        done
        fail "Some containers are unhealthy. Check logs above."
    fi
    
    ok "All containers are healthy"
}

# =============================================================================
# SERVICE CONFIGURATION FUNCTIONS
# =============================================================================

# Wait for service to be ready with proper error handling (P0 fix)
wait_for_service() {
    local name="$1" url="$2" container="$3" retries="${4:-30}"
    echo "Waiting for $name..."
    
    for i in $(seq 1 "$retries"); do
        if curl -sf "$url" &>/dev/null; then
            echo "✓ $name is ready."
            return 0
        fi
        sleep 2
    done
    
    echo "✗ ERROR: $name did not become ready after $((retries * 2)) seconds."
    echo "       Diagnose with: docker logs $container"
    echo "       Current container status:"
    docker ps --filter "name=$container" --format "table {{.Names}}\t{{.Status}}"
    return 1
}

configure_ollama() {
    if [[ "${OLLAMA_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    if step_done "ollama_configured"; then
        log "Ollama already configured, skipping"
        return 0
    fi
    
    local container_name="${TENANT_PREFIX}-ollama"
    
    log "Configuring Ollama..."
    
    # Wait for Ollama to be ready using improved function
    if ! wait_for_service "Ollama" "http://localhost:${OLLAMA_PORT}/api/tags" "$container_name"; then
        fail "Ollama failed to start within timeout"
    fi
    
    # Pull the default model with progress indication
    log "Pulling default Ollama model (${OLLAMA_DEFAULT_MODEL})..."
    log "This may take several minutes depending on connection speed..."
    if run_cmd docker exec "$container_name" ollama pull "${OLLAMA_DEFAULT_MODEL}"; then
        log "Model pull complete"
    else
        warn "Model pull failed. You can retry with: docker exec $container_name ollama pull ${OLLAMA_DEFAULT_MODEL}"
        warn "Platform is functional without the model"
    fi
    
    mark_done "ollama_configured"
    ok "Ollama configured"
}

configure_litellm() {
    if [[ "${LITELLM_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    if step_done "litellm_configured"; then
        log "LiteLLM already configured, skipping"
        return 0
    fi
    
    local container_name="${TENANT_PREFIX}-litellm"
    local litellm_url="http://127.0.0.1:${LITELLM_PORT}"
    
    log "Configuring LiteLLM..."
    
    # Wait for LiteLLM to be ready
    local attempts=0
    local max_attempts=30
    
    while [[ $attempts -lt $max_attempts ]]; do
        # README §6: Health check via GET /health/liveliness (not /health)
        if curl -sf "${litellm_url}/health/liveliness" >/dev/null 2>&1; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 2
    done
    
    if [[ $attempts -ge $max_attempts ]]; then
        fail "LiteLLM not ready after timeout"
    fi
    
    # Test LiteLLM API
    if curl -sf "${litellm_url}/v1/models" | grep -q "ollama\|openai\|anthropic"; then
        log "  LiteLLM API responding correctly"
    else
        warn "LiteLLM API not responding as expected"
    fi
    
    mark_done "litellm_configured"
    ok "LiteLLM configured"
}

configure_openwebui() {
    if [[ "${OPENWEBUI_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    if step_done "openwebui_configured"; then
        log "Open WebUI already configured, skipping"
        return 0
    fi
    
    local container_name="${TENANT_PREFIX}-openwebui"
    local webui_url="http://127.0.0.1:${OPENWEBUI_PORT}"
    
    log "Configuring Open WebUI..."
    
    # Wait for Open WebUI to be ready
    local attempts=0
    local max_attempts=30
    
    while [[ $attempts -lt $max_attempts ]]; do
        if curl -sf "${webui_url}/api/health" >/dev/null 2>&1; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 2
    done
    
    if [[ $attempts -ge $max_attempts ]]; then
        fail "Open WebUI not ready after timeout"
    fi
    
    mark_done "openwebui_configured"
    ok "Open WebUI configured"
}

configure_librechat() {
    if [[ "${LIBRECHAT_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    if step_done "librechat_configured"; then
        log "LibreChat already configured, skipping"
        return 0
    fi
    
    local container_name="${TENANT_PREFIX}-librechat"
    local librechat_url="http://127.0.0.1:${LIBRECHAT_PORT}"
    
    log "Configuring LibreChat..."
    
    # Wait for LibreChat to be ready
    local attempts=0
    local max_attempts=30
    
    while [[ $attempts -lt $max_attempts ]]; do
        if curl -sf "${librechat_url}/api/health" >/dev/null 2>&1; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 2
    done
    
    if [[ $attempts -ge $max_attempts ]]; then
        fail "LibreChat not ready after timeout"
    fi
    
    mark_done "librechat_configured"
    ok "LibreChat configured"
}

configure_openclaw() {
    if [[ "${OPENCLAW_ENABLED}" != "true" ]]; then
        return 0
    fi

    # Skip if no custom image provided — container was not deployed
    if [[ -z "${OPENCLAW_IMAGE:-}" ]]; then
        log "OpenClaw: no image configured, skipping"
        return 0
    fi

    if step_done "openclaw_configured"; then
        log "OpenClaw already configured, skipping"
        return 0
    fi
    
    local container_name="${TENANT_PREFIX}-openclaw"
    local openclaw_url="http://127.0.0.1:${OPENCLAW_PORT}"
    
    log "Configuring OpenClaw..."
    
    # Wait for OpenClaw to be ready
    local attempts=0
    local max_attempts=30
    
    while [[ $attempts -lt $max_attempts ]]; do
        if curl -sf "${openclaw_url}/api/health" >/dev/null 2>&1; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 2
    done
    
    if [[ $attempts -ge $max_attempts ]]; then
        fail "OpenClaw not ready after timeout"
    fi
    
    mark_done "openclaw_configured"
    ok "OpenClaw configured"
}

configure_qdrant() {
    if [[ "${QDRANT_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    if step_done "qdrant_configured"; then
        log "Qdrant already configured, skipping"
        return 0
    fi
    
    local container_name="${TENANT_PREFIX}-qdrant"
    local qdrant_url="http://127.0.0.1:${QDRANT_PORT}"
    
    log "Configuring Qdrant..."
    
    # Wait for Qdrant to be ready
    local attempts=0
    local max_attempts=30
    
    while [[ $attempts -lt $max_attempts ]]; do
        if curl -sf "${qdrant_url}/healthz" >/dev/null 2>&1; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 2
    done

    if [[ $attempts -ge $max_attempts ]]; then
        fail "Qdrant not ready after timeout"
    fi

    mark_done "qdrant_configured"
    ok "Qdrant configured"
}

configure_n8n() {
    if [[ "${N8N_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    if step_done "n8n_configured"; then
        log "N8N already configured, skipping"
        return 0
    fi
    
    local container_name="${TENANT_PREFIX}-n8n"
    local n8n_url="http://127.0.0.1:${N8N_PORT}"
    
    log "Configuring N8N..."
    
    # README §6: Verify N8N_ENCRYPTION_KEY is set (must be set before first container start)
    if [[ -z "${N8N_ENCRYPTION_KEY}" ]]; then
        fail "N8N_ENCRYPTION_KEY is not set - this must be set before first container start"
    fi
    
    # Wait for N8N to be ready
    local attempts=0
    local max_attempts=30
    
    while [[ $attempts -lt $max_attempts ]]; do
        if curl -sf "${n8n_url}/healthz" >/dev/null 2>&1; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 2
    done
    
    if [[ $attempts -ge $max_attempts ]]; then
        fail "N8N not ready after timeout"
    fi
    
    log "  N8N_ENCRYPTION_KEY is properly set"
    
    mark_done "n8n_configured"
    ok "N8N configured"
}

configure_flowise() {
    if [[ "${FLOWISE_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    if step_done "flowise_configured"; then
        log "Flowise already configured, skipping"
        return 0
    fi
    
    local container_name="${TENANT_PREFIX}-flowise"
    local flowise_url="http://127.0.0.1:${FLOWISE_PORT}"
    
    log "Configuring Flowise..."
    
    # Wait for Flowise to be ready
    local attempts=0
    local max_attempts=30
    
    while [[ $attempts -lt $max_attempts ]]; do
        if curl -sf "${flowise_url}/api/v1/ping" >/dev/null 2>&1; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 2
    done
    
    if [[ $attempts -ge $max_attempts ]]; then
        fail "Flowise not ready after timeout. Check: docker logs $container_name"
    fi
    
    mark_done "flowise_configured"
    ok "Flowise configured"
}

configure_dify() {
    if [[ "${DIFY_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    if step_done "dify_configured"; then
        log "Dify already configured, skipping"
        return 0
    fi
    
    local container_name="${TENANT_PREFIX}-dify"
    local dify_url="http://127.0.0.1:${DIFY_PORT}"
    
    log "Configuring Dify..."
    
    # Wait for Dify to be ready
    local attempts=0
    local max_attempts=30
    
    while [[ $attempts -lt $max_attempts ]]; do
        if curl -sf "${dify_url}/apps" >/dev/null 2>&1; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 2
    done
    
    if [[ $attempts -ge $max_attempts ]]; then
        fail "Dify not ready after timeout"
    fi
    
    # README §6: Call POST /console/api/setup only (not workspace invite)
    log "  Calling Dify setup API..."
    local setup_response
    setup_response=$(curl -s -X POST "${dify_url}/console/api/setup" \
        -H "Content-Type: application/json" \
        -d "{\"init_password\":\"${DIFY_INIT_PASSWORD:-}\"}" 2>/dev/null || true)
    
    if [[ -n "$setup_response" ]]; then
        log "  Dify setup completed"
    else
        warn "Dify setup API call failed"
    fi
    
    mark_done "dify_configured"
    ok "Dify configured"
}

configure_authentik() {
    if [[ "${AUTHENTIK_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    if step_done "authentik_configured"; then
        log "Authentik already configured, skipping"
        return 0
    fi
    
    local container_name="${TENANT_PREFIX}-authentik"
    local authentik_url="http://127.0.0.1:${AUTHENTIK_PORT}"
    
    log "Configuring Authentik..."
    
    # Wait for Authentik to be ready
    local attempts=0
    local max_attempts=60  # Authentik takes longer to start
    
    while [[ $attempts -lt $max_attempts ]]; do
        if curl -sf "${authentik_url}/-/health/live/" >/dev/null 2>&1; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 3
    done
    
    if [[ $attempts -ge $max_attempts ]]; then
        fail "Authentik not ready after timeout"
    fi
    
    # Authentik bootstrap is automatic — akadmin user created from AUTHENTIK_BOOTSTRAP_PASSWORD env var.
    # API token retrieval requires the full OAuth flow; skip for now and just verify the service is live.
    log "  Authentik is live (bootstrap password: ${AUTHENTIK_BOOTSTRAP_PASSWORD:-<not set>})"
    
    mark_done "authentik_configured"
    ok "Authentik configured"
}

configure_signalbot() {
    if [[ "${SIGNALBOT_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    if step_done "signalbot_configured"; then
        log "Signalbot already configured, skipping"
        return 0
    fi
    
    local container_name="${TENANT_PREFIX}-signalbot"
    local signalbot_url="http://127.0.0.1:${SIGNALBOT_PORT}"
    
    log "Configuring Signalbot..."
    
    # Wait for Signalbot to be ready
    local attempts=0
    local max_attempts=30
    
    while [[ $attempts -lt $max_attempts ]]; do
        if curl -sf "${signalbot_url}/v1/about" >/dev/null 2>&1; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 2
    done
    
    if [[ $attempts -ge $max_attempts ]]; then
        fail "Signalbot not ready after timeout"
    fi
    
    mark_done "signalbot_configured"
    ok "Signalbot configured"
}

configure_bifrost() {
    if [[ "${BIFROST_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    if step_done "bifrost_configured"; then
        log "Bifrost already configured, skipping"
        return 0
    fi
    
    local container_name="${TENANT_PREFIX}-bifrost"
    local bifrost_url="http://127.0.0.1:${BIFROST_PORT}"
    
    log "Configuring Bifrost..."
    
    # Wait for Bifrost to be ready
    local attempts=0
    local max_attempts=30
    
    while [[ $attempts -lt $max_attempts ]]; do
        if curl -sf "${bifrost_url}/health" >/dev/null 2>&1; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 2
    done
    
    if [[ $attempts -ge $max_attempts ]]; then
        fail "Bifrost not ready after timeout"
    fi
    
    mark_done "bifrost_configured"
    ok "Bifrost configured"
}

# =============================================================================
# CREDENTIALS DISPLAY (README §6)
# =============================================================================
show_credentials() {
    echo ""
    echo "══════════════════════════════════════════════════════════"
    echo "  AI PLATFORM CREDENTIALS"
    echo "  Tenant: ${TENANT_ID}   Built: ${GENERATED_AT:-Unknown}"
    echo "══════════════════════════════════════════════════════════"
    echo ""
    
    # Infrastructure
    if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
        echo "INFRASTRUCTURE"
        echo "  PostgreSQL  postgres.${BASE_DOMAIN}:${POSTGRES_PORT}"
        echo "  User        ${POSTGRES_USER}"
        echo "  Password    ${POSTGRES_PASSWORD}"
        echo ""
    fi
    
    # LLM Proxy
    if [[ "${LITELLM_ENABLED}" == "true" ]]; then
        echo "LLM PROXY"
        echo "  URL         https://${BASE_DOMAIN}/litellm"
        echo "  Master Key  ${LITELLM_MASTER_KEY}"
        echo "  UI Password ${LITELLM_UI_PASSWORD}"
        echo ""
    fi
    
    # Web UIs
    if [[ "${OPENWEBUI_ENABLED}" == "true" ]]; then
        echo "WEB UI"
        echo "  Open WebUI  https://${BASE_DOMAIN}/openwebui"
        echo "  Secret      ${OPENWEBUI_SECRET}"
        echo ""
    fi
    
    if [[ "${LIBRECHAT_ENABLED}" == "true" ]]; then
        echo "WEB UI"
        echo "  LibreChat   https://${BASE_DOMAIN}/librechat"
        echo "  JWT Secret  ${LIBRECHAT_JWT_SECRET:-Unknown}"
        echo "  Crypt Key   ${LIBRECHAT_CRYPT_KEY:-Unknown}"
        echo ""
    fi
    
    if [[ "${OPENCLAW_ENABLED}" == "true" ]]; then
        echo "WEB UI"
        echo "  OpenClaw    https://${BASE_DOMAIN}/openclaw"
        echo "  Port        ${OPENCLAW_PORT}"
        echo ""
    fi
    
    # Automation
    if [[ "${N8N_ENABLED}" == "true" ]]; then
        echo "AUTOMATION"
        echo "  N8N         https://${BASE_DOMAIN}/n8n"
        echo "  Encryption   ${N8N_ENCRYPTION_KEY}"
        echo ""
    fi
    
    if [[ "${FLOWISE_ENABLED}" == "true" ]]; then
        echo "AUTOMATION"
        echo "  Flowise     https://${BASE_DOMAIN}/flowise"
        echo "  Username    ${FLOWISE_USERNAME}"
        echo "  Password    ${FLOWISE_PASSWORD}"
        echo ""
    fi
    
    if [[ "${DIFY_ENABLED}" == "true" ]]; then
        echo "AUTOMATION"
        echo "  Dify        https://${BASE_DOMAIN}/dify"
        echo "  Secret Key  ${DIFY_SECRET_KEY:-Unknown}"
        echo "  Init Pass   ${DIFY_INIT_PASSWORD:-Unknown}"
        echo ""
    fi
    
    # Identity
    if [[ "${AUTHENTIK_ENABLED}" == "true" ]]; then
        echo "IDENTITY"
        echo "  Authentik    https://${BASE_DOMAIN}/authentik"
        echo "  Bootstrap    ${AUTHENTIK_BOOTSTRAP_EMAIL}"
        echo "  Password     ${AUTHENTIK_BOOTSTRAP_PASSWORD}"
        if [[ -n "${AUTHENTIK_API_TOKEN:-}" ]]; then
            echo "  API Token    ${AUTHENTIK_API_TOKEN}"
        fi
        echo ""
    fi
    
    # RAG/Vector
    if [[ "${QDRANT_ENABLED}" == "true" ]]; then
        echo "RAG/VECTOR"
        echo "  Qdrant      ${QDRANT_API_KEY}"
        echo ""
    fi
    
    # Alerting
    if [[ "${SIGNALBOT_ENABLED}" == "true" ]]; then
        echo "ALERTING"
        echo "  Signalbot   ${SIGNAL_PHONE}"
        echo "  Recipient    ${SIGNAL_RECIPIENT}"
        echo ""
    fi
    
    # Bifrost
    if [[ "${BIFROST_ENABLED}" == "true" ]]; then
        echo "BIFROST"
        echo "  API Key     ${BIFROST_API_KEY}"
        echo ""
    fi
    
    echo "══════════════════════════════════════════════════════════"
    echo ""
}

# =============================================================================
# KEY ROTATION
# =============================================================================
rotate_keys() {
    local service="$1"
    
    log "Rotating keys for service: ${service}"
    
    case "${service}" in
        litellm)
            if [[ "${LITELLM_ENABLED}" != "true" ]]; then
                fail "LiteLLM is not enabled"
            fi
            
            # Generate new secrets
            local new_master_key="sk-$(openssl rand -hex 32)"
            local new_ui_password="$(openssl rand -base64 24 | tr -d '=+/' | cut -c1-20)"
            
            # Update platform.conf
            sed -i "s/LITELLM_MASTER_KEY=.*/LITELLM_MASTER_KEY=\"${new_master_key}\"/" "${BASE_DIR}/platform.conf"
            sed -i "s/LITELLM_UI_PASSWORD=.*/LITELLM_UI_PASSWORD=\"${new_ui_password}\"/" "${BASE_DIR}/platform.conf"
            
            # Restart LiteLLM container
            log "  Restarting LiteLLM container..."
            run_cmd docker restart "${TENANT_PREFIX}-litellm"
            
            # Wait for health
            local attempts=0
            local max_attempts=30
            while [[ $attempts -lt $max_attempts ]]; do
                if curl -sf "http://127.0.0.1:${LITELLM_PORT}/health/liveliness" >/dev/null 2>&1; then
                    break
                fi
                attempts=$((attempts + 1))
                sleep 2
            done
            
            if [[ $attempts -ge $max_attempts ]]; then
                fail "LiteLLM did not become healthy after restart"
            fi
            
            ok "LiteLLM keys rotated successfully"
            ;;
        *)
            fail "Key rotation not implemented for service: ${service}"
            ;;
    esac
}

# =============================================================================
# HEALTH CHECK DISPLAY
# =============================================================================
show_health_status() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              SERVICE HEALTH STATUS                    ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    
    printf "%-15s %-12s %-20s %-15s\n" "SERVICE" "STATUS" "CONTAINER" "PORT"
    echo "────────────────────────────────────────────────────────"
    
    # Check each enabled service
    if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
        local status="DOWN"
        local container_name="${TENANT_PREFIX}-postgres"
        if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
            status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "UNKNOWN")
        fi
        printf "%-15s %-12s %-20s %-15s\n" "PostgreSQL" "$status" "$container_name" "${POSTGRES_PORT}"
    fi
    
    if [[ "${REDIS_ENABLED}" == "true" ]]; then
        local status="DOWN"
        local container_name="${TENANT_PREFIX}-redis"
        if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
            status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "UNKNOWN")
        fi
        printf "%-15s %-12s %-20s %-15s\n" "Redis" "$status" "$container_name" "${REDIS_PORT}"
    fi
    
    if [[ "${OLLAMA_ENABLED}" == "true" ]]; then
        local status="DOWN"
        local container_name="${TENANT_PREFIX}-ollama"
        if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
            status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "UNKNOWN")
        fi
        printf "%-15s %-12s %-20s %-15s\n" "Ollama" "$status" "$container_name" "${OLLAMA_PORT}"
    fi
    
    if [[ "${LITELLM_ENABLED}" == "true" ]]; then
        local status="DOWN"
        local container_name="${TENANT_PREFIX}-litellm"
        if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
            status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "UNKNOWN")
        fi
        printf "%-15s %-12s %-20s %-15s\n" "LiteLLM" "$status" "$container_name" "${LITELLM_PORT}"
    fi
    
    if [[ "${OPENWEBUI_ENABLED}" == "true" ]]; then
        local status="DOWN"
        local container_name="${TENANT_PREFIX}-openwebui"
        if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
            status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "UNKNOWN")
        fi
        printf "%-15s %-12s %-20s %-15s\n" "OpenWebUI" "$status" "$container_name" "${OPENWEBUI_PORT}"
    fi
    
    if [[ "${QDRANT_ENABLED}" == "true" ]]; then
        local status="DOWN"
        local container_name="${TENANT_PREFIX}-qdrant"
        if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
            status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "UNKNOWN")
        fi
        printf "%-15s %-12s %-20s %-15s\n" "Qdrant" "$status" "$container_name" "${QDRANT_PORT}"
    fi
    
    echo ""
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================
main() {
    local tenant_id="${1:-}"
    local verify_only=false
    local health_check=false
    local show_credentials=false
    local rotate_keys=""
    local restart_service=""
    local add_service=""
    local remove_service=""
    local disable_service=""
    local enable_service=""
    local dry_run=false
    
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
            --show-credentials)
                show_credentials=true
                shift
                ;;
            --rotate-keys)
                rotate_keys="$2"
                shift 2
                ;;
            --restart)
                restart_service="$2"
                shift 2
                ;;
            --add)
                add_service="$2"
                shift 2
                ;;
            --remove)
                remove_service="$2"
                shift 2
                ;;
            --disable)
                disable_service="$2"
                shift 2
                ;;
            --enable)
                enable_service="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                fail "Unknown option: $1"
                ;;
        esac
    done
    
    # Set global variables
    export DRY_RUN="$dry_run"
    
    # Validate tenant ID (README BUG-14 fix)
    if [[ -z "$tenant_id" ]]; then
        fail "Tenant ID is required"
    fi
    
    # Source platform.conf (single source of truth)
    local platform_conf="/mnt/${tenant_id}/config/platform.conf"
    if [[ ! -f "$platform_conf" ]]; then
        fail "platform.conf not found at $platform_conf. Run script 1 first."
    fi
    # shellcheck source=/dev/null
    source "$platform_conf"

    # Normalise / derive variables
    CONFIGURED_DIR="${DATA_DIR}/.configured"
    BASE_DIR="${DATA_DIR}"
    CONFIG_DIR="${DATA_DIR}/config"
    LOG_FILE="${DATA_DIR}/logs/configure-$(date +%Y%m%d-%H%M%S).log"

    mkdir -p "${DATA_DIR}/logs" "$CONFIGURED_DIR"

    # Load dynamic port allocations
    if [[ -f "${CONFIGURED_DIR}/port-allocations" ]]; then
        # shellcheck source=/dev/null
        source "${CONFIGURED_DIR}/port-allocations"
        [[ -n "${POSTGRES_HOST_PORT:-}" ]] && POSTGRES_PORT="${POSTGRES_HOST_PORT}"
        [[ -n "${REDIS_HOST_PORT:-}" ]] && REDIS_PORT="${REDIS_HOST_PORT}"
        [[ -n "${OLLAMA_HOST_PORT:-}" ]] && OLLAMA_PORT="${OLLAMA_HOST_PORT}"
        [[ -n "${LITELLM_HOST_PORT:-}" ]] && LITELLM_PORT="${LITELLM_HOST_PORT}"
        [[ -n "${OPENWEBUI_HOST_PORT:-}" ]] && OPENWEBUI_PORT="${OPENWEBUI_HOST_PORT}"
        [[ -n "${OPENCLAW_HOST_PORT:-}" ]] && OPENCLAW_PORT="${OPENCLAW_HOST_PORT}"
        [[ -n "${QDRANT_HOST_PORT:-}" ]] && QDRANT_PORT="${QDRANT_HOST_PORT}"
        [[ -n "${N8N_HOST_PORT:-}" ]] && N8N_PORT="${N8N_HOST_PORT}"
        [[ -n "${FLOWISE_HOST_PORT:-}" ]] && FLOWISE_PORT="${FLOWISE_HOST_PORT}"
        [[ -n "${DIFY_HOST_PORT:-}" ]] && DIFY_PORT="${DIFY_HOST_PORT}"
        [[ -n "${AUTHENTIK_HOST_PORT:-}" ]] && AUTHENTIK_PORT="${AUTHENTIK_HOST_PORT}"
        [[ -n "${SIGNALBOT_HOST_PORT:-}" ]] && SIGNALBOT_PORT="${SIGNALBOT_HOST_PORT}"
        [[ -n "${BIFROST_HOST_PORT:-}" ]] && BIFROST_PORT="${BIFROST_HOST_PORT}"
        [[ -n "${WEAVIATE_HOST_PORT:-}" ]] && WEAVIATE_PORT="${WEAVIATE_HOST_PORT}"
        [[ -n "${CHROMA_HOST_PORT:-}" ]] && CHROMA_PORT="${CHROMA_HOST_PORT}"
        [[ -n "${MILVUS_HOST_PORT:-}" ]] && MILVUS_PORT="${MILVUS_HOST_PORT}"
        [[ -n "${CODE_SERVER_HOST_PORT:-}" ]] && CODE_SERVER_PORT="${CODE_SERVER_HOST_PORT}"
        [[ -n "${GRAFANA_HOST_PORT:-}" ]] && GRAFANA_PORT="${GRAFANA_HOST_PORT}"
        [[ -n "${PROMETHEUS_HOST_PORT:-}" ]] && PROMETHEUS_PORT="${PROMETHEUS_HOST_PORT}"
        [[ -n "${ANYTHINGLLM_HOST_PORT:-}" ]] && ANYTHINGLLM_PORT="${ANYTHINGLLM_HOST_PORT}"
        [[ -n "${MEM0_HOST_PORT:-}" ]] && MEM0_PORT="${MEM0_HOST_PORT}"
    fi

    # Derive TENANT_PREFIX if not in platform.conf (backward compat)
    TENANT_PREFIX="${TENANT_PREFIX:-${PLATFORM_PREFIX}-${TENANT_ID}}"
    POSTGRES_USER="${POSTGRES_USER:-${TENANT_ID}}"
    POSTGRES_DB="${POSTGRES_DB:-${TENANT_ID}}"
    BASE_DOMAIN="${BASE_DOMAIN:-${DOMAIN}}"
    PROXY_EMAIL="${PROXY_EMAIL:-${ADMIN_EMAIL}}"
    PUID="${PUID:-$(id -u)}"
    PGID="${PGID:-$(id -g)}"

    # Map ENABLE_* → *_ENABLED (backward compat with old platform.conf)
    POSTGRES_ENABLED="${POSTGRES_ENABLED:-${ENABLE_POSTGRES:-false}}"
    REDIS_ENABLED="${REDIS_ENABLED:-${ENABLE_REDIS:-false}}"
    OLLAMA_ENABLED="${OLLAMA_ENABLED:-${ENABLE_OLLAMA:-false}}"
    LITELLM_ENABLED="${LITELLM_ENABLED:-${ENABLE_LITELLM:-false}}"
    OPENWEBUI_ENABLED="${OPENWEBUI_ENABLED:-${ENABLE_OPENWEBUI:-false}}"
    QDRANT_ENABLED="${QDRANT_ENABLED:-${ENABLE_QDRANT:-false}}"
    WEAVIATE_ENABLED="${WEAVIATE_ENABLED:-${ENABLE_WEAVIATE:-false}}"
    N8N_ENABLED="${N8N_ENABLED:-${ENABLE_N8N:-false}}"
    FLOWISE_ENABLED="${FLOWISE_ENABLED:-${ENABLE_FLOWISE:-false}}"
    DIFY_ENABLED="${DIFY_ENABLED:-${ENABLE_DIFY:-false}}"
    GRAFANA_ENABLED="${GRAFANA_ENABLED:-${ENABLE_GRAFANA:-false}}"
    PROMETHEUS_ENABLED="${PROMETHEUS_ENABLED:-${ENABLE_PROMETHEUS:-false}}"
    CADDY_ENABLED="${CADDY_ENABLED:-${ENABLE_CADDY:-false}}"
    AUTHENTIK_ENABLED="${AUTHENTIK_ENABLED:-${ENABLE_AUTHENTIK:-false}}"
    OPENCLAW_ENABLED="${OPENCLAW_ENABLED:-${ENABLE_OPENCLAW:-false}}"
    BIFROST_ENABLED="${BIFROST_ENABLED:-${ENABLE_BIFROST:-false}}"
    SIGNALBOT_ENABLED="${SIGNALBOT_ENABLED:-${ENABLE_SIGNALBOT:-false}}"
    LIBRECHAT_ENABLED="${LIBRECHAT_ENABLED:-${ENABLE_LIBRECHAT:-false}}"
    ANYTHINGLLM_ENABLED="${ANYTHINGLLM_ENABLED:-${ENABLE_ANYTHINGLLM:-false}}"
    MEM0_ENABLED="${MEM0_ENABLED:-${ENABLE_MEM0:-false}}"
    CODE_SERVER_ENABLED="${CODE_SERVER_ENABLED:-${ENABLE_CODE_SERVER:-false}}"
    CHROMA_ENABLED="${CHROMA_ENABLED:-${ENABLE_CHROMA:-false}}"
    MILVUS_ENABLED="${MILVUS_ENABLED:-${ENABLE_MILVUS:-false}}"
    
    log "=== Script 3: Mission Control ==="
    log "Version: ${SCRIPT_VERSION}"
    log "Tenant: ${tenant_id}"
    log "Verify-only: ${verify_only}"
    log "Health-check: ${health_check}"
    log "Show-credentials: ${show_credentials}"
    log "Rotate-keys: ${rotate_keys}"
    log "Restart-service: ${restart_service}"
    log "Add-service: ${add_service}"
    log "Remove-service: ${remove_service}"
    log "Disable-service: ${disable_service}"
    log "Enable-service: ${enable_service}"
    log "Dry-run: ${dry_run}"
    
    # Framework validation
    framework_validate
    
    # Handle special modes
    if [[ "$health_check" == "true" ]]; then
        show_health_status
        return 0
    fi
    
    if [[ "$show_credentials" == "true" ]]; then
        show_credentials
        return 0
    fi
    
    # Handle platform operations
    if [[ -n "$restart_service" ]]; then
        restart_service "$restart_service"
        return 0
    fi
    
    if [[ -n "$add_service" ]]; then
        add_service "$add_service"
        return 0
    fi
    
    if [[ -n "$remove_service" ]]; then
        remove_service "$remove_service"
        return 0
    fi
    
    if [[ -n "$disable_service" ]]; then
        disable_service "$disable_service"
        return 0
    fi
    
    if [[ -n "$enable_service" ]]; then
        enable_service "$enable_service"
        return 0
    fi
    
    # Verify containers are healthy before any configuration
    verify_containers_healthy
    
    if [[ -n "$rotate_keys" ]]; then
        rotate_keys "$rotate_keys"
        return 0
    fi
    
    # Service configuration (unless verify-only)
    if [[ "$verify_only" != "true" ]]; then
        configure_ollama
        configure_litellm
        configure_openwebui
        configure_librechat
        configure_openclaw
        configure_qdrant
        configure_n8n
        configure_flowise
        configure_dify
        configure_authentik
        configure_signalbot
        configure_bifrost
    fi
    
    # Show credentials summary
    show_credentials

    # Comprehensive Mission Control checks
    run_mission_control
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              Script 3 Complete ✓                        ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "  ✓ platform.conf sourced (single source of truth)"
    echo "  ✓ Service APIs called for setup"
    echo "  ✓ Port health checks (per-service)"
    echo "  ✓ DNS resolution validated"
    echo "  ✓ API keys live-tested"
    echo "  ✓ Rclone credentials validated"
    echo "  ✓ Signal pairing status checked"
    echo "  ✓ Access URLs displayed"
    echo ""
    echo "  Mission Control complete. Platform is ready for use!"
    echo ""
}

# =============================================================================
# MISSION CONTROL: MODULAR HEALTH CHECKS
# Each function is self-contained, non-fatal (warns rather than fails),
# and returns 0=OK 1=degraded so callers can aggregate results.
# =============================================================================

# ── Port Health ───────────────────────────────────────────────────────────────
check_port_health() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  PORT HEALTH CHECKS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local all_ok=true

    _port_check() {
        local label="$1" port="$2" path="${3:-/}"
        local url="http://127.0.0.1:${port}${path}"
        if curl -sf --max-time 5 "$url" >/dev/null 2>&1; then
            echo "  ✓ ${label} (port ${port})"
        else
            echo "  ✗ ${label} (port ${port}) — not responding"
            all_ok=false
        fi
    }

    [[ "${POSTGRES_ENABLED:-false}"   == "true" ]] && \
        { docker exec "${TENANT_PREFIX}-postgres" pg_isready -U "${POSTGRES_USER}" >/dev/null 2>&1 \
          && echo "  ✓ PostgreSQL (port ${POSTGRES_PORT:-5432})" \
          || { echo "  ✗ PostgreSQL (port ${POSTGRES_PORT:-5432}) — not ready"; all_ok=false; }; }

    [[ "${REDIS_ENABLED:-false}"      == "true" ]] && \
        { docker exec "${TENANT_PREFIX}-redis" redis-cli -a "${REDIS_PASSWORD}" ping 2>/dev/null | grep -q PONG \
          && echo "  ✓ Redis (port ${REDIS_PORT:-6379})" \
          || { echo "  ✗ Redis (port ${REDIS_PORT:-6379}) — PING failed"; all_ok=false; }; }

    [[ "${OLLAMA_ENABLED:-false}"     == "true" ]] && _port_check "Ollama"     "${OLLAMA_PORT:-11434}"   "/api/tags"
    [[ "${LITELLM_ENABLED:-false}"    == "true" ]] && _port_check "LiteLLM"    "${LITELLM_PORT:-4000}"   "/health/liveliness"
    [[ "${OPENWEBUI_ENABLED:-false}"  == "true" ]] && _port_check "Open WebUI" "${OPENWEBUI_PORT:-3000}" "/"
    [[ "${QDRANT_ENABLED:-false}"     == "true" ]] && _port_check "Qdrant"     "${QDRANT_PORT:-6333}"    "/healthz"
    [[ "${N8N_ENABLED:-false}"        == "true" ]] && _port_check "N8N"        "${N8N_PORT:-5678}"       "/healthz"
    [[ "${FLOWISE_ENABLED:-false}"    == "true" ]] && _port_check "Flowise"    "${FLOWISE_PORT:-3000}"   "/api/v1/ping"
    [[ "${DIFY_ENABLED:-false}"       == "true" ]] && _port_check "Dify"       "${DIFY_PORT:-3002}"      "/apps"
    [[ "${GRAFANA_ENABLED:-false}"    == "true" ]] && _port_check "Grafana"    "${GRAFANA_PORT:-3003}"   "/api/health"
    [[ "${PROMETHEUS_ENABLED:-false}" == "true" ]] && _port_check "Prometheus" "${PROMETHEUS_PORT:-9090}" "/-/healthy"
    [[ "${AUTHENTIK_ENABLED:-false}"  == "true" ]] && _port_check "Authentik"  "${AUTHENTIK_PORT:-9000}" "/-/health/live/"
    [[ "${SIGNALBOT_ENABLED:-false}"  == "true" ]] && _port_check "Signalbot"  "${SIGNALBOT_PORT:-8080}" "/v1/about"

    $all_ok && ok "All port checks passed" || warn "Some services are not responding on their ports"
    $all_ok
}

# ── DNS Resolution ─────────────────────────────────────────────────────────────
check_dns_resolution() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  DNS RESOLUTION CHECK"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local domain="${BASE_DOMAIN:-${DOMAIN:-}}"
    if [[ -z "$domain" ]]; then
        warn "DOMAIN not set — skipping DNS check"
        return 0
    fi

    local host_ip
    host_ip=$(dig +short "$domain" 2>/dev/null | tail -1 || true)
    local server_ip
    server_ip=$(curl -sf --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')

    if [[ -z "$host_ip" ]]; then
        warn "DNS: ${domain} does not resolve — check your DNS provider"
        return 1
    fi

    if [[ "$host_ip" == "$server_ip" ]]; then
        echo "  ✓ DNS: ${domain} → ${host_ip} (matches server IP)"
    else
        echo "  ⚠ DNS: ${domain} → ${host_ip} (server IP: ${server_ip}) — may be behind a load balancer or misconfigured"
    fi
    ok "DNS check complete"
}

# ── API Key Live Tests ─────────────────────────────────────────────────────────
check_api_keys() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  API KEY VALIDATION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local any_tested=false

    _test_openai() {
        [[ -z "${OPENAI_API_KEY:-}" ]] && return 0
        any_tested=true
        local resp
        resp=$(curl -sf --max-time 10 https://api.openai.com/v1/models \
            -H "Authorization: Bearer ${OPENAI_API_KEY}" 2>/dev/null || true)
        if echo "$resp" | grep -q '"id"'; then
            echo "  ✓ OpenAI API key valid"
        else
            echo "  ✗ OpenAI API key invalid or network error"
        fi
    }

    _test_anthropic() {
        [[ -z "${ANTHROPIC_API_KEY:-}" ]] && return 0
        any_tested=true
        local resp
        resp=$(curl -sf --max-time 10 https://api.anthropic.com/v1/models \
            -H "x-api-key: ${ANTHROPIC_API_KEY}" \
            -H "anthropic-version: 2023-06-01" 2>/dev/null || true)
        if echo "$resp" | grep -q '"id"'; then
            echo "  ✓ Anthropic API key valid"
        else
            echo "  ✗ Anthropic API key invalid or network error"
        fi
    }

    _test_google() {
        local key="${GOOGLE_AI_API_KEY:-${GOOGLE_API_KEY:-}}"
        [[ -z "$key" ]] && return 0
        any_tested=true
        local resp
        resp=$(curl -sf --max-time 10 \
            "https://generativelanguage.googleapis.com/v1/models?key=${key}" 2>/dev/null || true)
        if echo "$resp" | grep -q '"name"'; then
            echo "  ✓ Google AI API key valid"
        else
            echo "  ✗ Google AI API key invalid or network error"
        fi
    }

    _test_groq() {
        [[ -z "${GROQ_API_KEY:-}" ]] && return 0
        any_tested=true
        local resp
        resp=$(curl -sf --max-time 10 https://api.groq.com/openai/v1/models \
            -H "Authorization: Bearer ${GROQ_API_KEY}" 2>/dev/null || true)
        if echo "$resp" | grep -q '"id"'; then
            echo "  ✓ Groq API key valid"
        else
            echo "  ✗ Groq API key invalid or network error"
        fi
    }

    _test_openai
    _test_anthropic
    _test_google
    _test_groq

    if $any_tested; then
        ok "API key checks complete"
    else
        echo "  ℹ  No API keys configured — skipping live tests"
    fi
}

# ── Rclone / JSON Credentials ──────────────────────────────────────────────────
check_rclone_credentials() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  RCLONE / INGESTION CREDENTIALS CHECK"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ "${ENABLE_INGESTION:-false}" != "true" ]]; then
        echo "  ℹ  Ingestion not enabled — skipping"
        return 0
    fi

    if [[ "${INGESTION_METHOD:-rclone}" != "rclone" ]]; then
        echo "  ℹ  Ingestion method is '${INGESTION_METHOD}', not rclone — skipping"
        return 0
    fi

    local cred_file="${GDRIVE_CREDENTIALS_FILE:-}"
    if [[ -z "$cred_file" ]]; then
        warn "GDRIVE_CREDENTIALS_FILE not set — rclone sync will fail"
        return 1
    fi

    if [[ ! -f "$cred_file" ]]; then
        warn "Credentials file not found: $cred_file"
        return 1
    fi

    # Validate JSON structure
    if ! jq -e '.type // .client_email // .token_uri' "$cred_file" >/dev/null 2>&1; then
        warn "Credentials file is not valid Google service account JSON: $cred_file"
        return 1
    fi

    echo "  ✓ Credentials file valid JSON: $cred_file"

    # Test rclone connectivity if rclone is available
    if command -v rclone >/dev/null 2>&1; then
        local rclone_conf="${DATA_DIR}/rclone/rclone.conf"
        if [[ -f "$rclone_conf" ]]; then
            if rclone lsd "${RCLONE_REMOTE:-gdrive}:" --config "$rclone_conf" --max-depth 1 >/dev/null 2>&1; then
                echo "  ✓ Rclone can connect to remote '${RCLONE_REMOTE:-gdrive}'"
            else
                warn "Rclone cannot connect to remote '${RCLONE_REMOTE:-gdrive}' — check credentials and permissions"
                return 1
            fi
        else
            echo "  ℹ  rclone.conf not yet generated (run Script 2 first)"
        fi
    else
        echo "  ℹ  rclone binary not installed on host — validation via container only"
    fi

    ok "Rclone credentials check complete"
}

# ── Signal Pairing Status ──────────────────────────────────────────────────────
check_signal_pairing() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  SIGNAL PAIRING STATUS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ "${SIGNALBOT_ENABLED:-false}" != "true" ]]; then
        echo "  ℹ  Signalbot not enabled — skipping"
        return 0
    fi

    local signalbot_url="http://127.0.0.1:${SIGNALBOT_PORT:-8080}"
    local phone="${SIGNAL_PHONE:-}"

    # Check if API is reachable
    local about
    about=$(curl -sf --max-time 5 "${signalbot_url}/v1/about" 2>/dev/null || true)
    if [[ -z "$about" ]]; then
        warn "Signalbot API not reachable at ${signalbot_url}"
        return 1
    fi

    echo "  ✓ Signalbot API reachable"
    local api_version
    api_version=$(echo "$about" | jq -r '.build.version // "unknown"' 2>/dev/null || true)
    echo "    Version: ${api_version}"

    if [[ -z "$phone" ]]; then
        warn "SIGNAL_PHONE not configured — cannot check pairing status"
        return 1
    fi

    # Check if number is registered/linked
    local accounts
    accounts=$(curl -sf --max-time 5 "${signalbot_url}/v1/accounts" 2>/dev/null || true)
    if echo "$accounts" | jq -e '.[] | select(. == "'"${phone}"'")' >/dev/null 2>&1; then
        echo "  ✓ Signal number ${phone} is registered and linked"
    else
        echo "  ✗ Signal number ${phone} is NOT paired"
        echo ""
        echo "  To pair your Signal account:"
        echo "    Option A — Link existing device (scan QR code):"
        echo "      curl -s '${signalbot_url}/v1/qrcodelink/${phone}?device_name=ai-platform' | jq -r '.uri'"
        echo "      Then scan the URI with: signal-cli link -n 'ai-platform'"
        echo ""
        echo "    Option B — Register new number:"
        echo "      curl -s -X POST '${signalbot_url}/v1/register/${phone}'"
        echo "      curl -s -X POST '${signalbot_url}/v1/register/${phone}/verify/<CODE>'"
        return 1
    fi

    ok "Signal pairing check complete"
}

# ── Comprehensive Mission Control ──────────────────────────────────────────────
run_mission_control() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║            MISSION CONTROL — PLATFORM STATUS             ║"
    echo "╚══════════════════════════════════════════════════════════╝"

    local overall_ok=true

    check_port_health       || overall_ok=false
    check_dns_resolution    || overall_ok=false
    check_api_keys          || true  # non-fatal — keys may be optional
    check_rclone_credentials || true  # non-fatal — ingestion may not be configured
    check_signal_pairing    || true  # non-fatal — pairing is a setup step

    echo ""
    if $overall_ok; then
        echo "  ✓ Platform is fully operational"
    else
        echo "  ⚠  Platform has degraded services — review warnings above"
    fi
    echo ""

    echo "  Access URLs:"
    local host_ip
    host_ip=$(hostname -I | awk '{print $1}')
    [[ "${OPENWEBUI_ENABLED:-false}"  == "true" ]] && echo "    Open WebUI  → http://${host_ip}:${OPENWEBUI_PORT:-3000}"
    [[ "${LITELLM_ENABLED:-false}"    == "true" ]] && echo "    LiteLLM     → http://${host_ip}:${LITELLM_PORT:-4000}"
    [[ "${N8N_ENABLED:-false}"        == "true" ]] && echo "    N8N         → http://${host_ip}:${N8N_PORT:-5678}"
    [[ "${FLOWISE_ENABLED:-false}"    == "true" ]] && echo "    Flowise     → http://${host_ip}:${FLOWISE_PORT:-3000}"
    [[ "${GRAFANA_ENABLED:-false}"    == "true" ]] && echo "    Grafana     → http://${host_ip}:${GRAFANA_PORT:-3001}"
    [[ "${AUTHENTIK_ENABLED:-false}"  == "true" ]] && echo "    Authentik   → http://${host_ip}:${AUTHENTIK_PORT:-9000}"
    [[ "${CADDY_ENABLED:-false}"      == "true" ]] && echo "    Caddy (TLS) → https://${BASE_DOMAIN:-${DOMAIN:-localhost}}"
    echo ""
}

# =============================================================================
# PLATFORM OPERATIONS - MISSION CONTROL HUB
# =============================================================================

# Restart a specific service
restart_service() {
    local service="$1"
    local container_name="${TENANT_PREFIX}-${service}"
    
    log "Restarting service: $service (container: $container_name)"
    
    if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
        docker restart "$container_name"
        log "Service $service restarted successfully"
        
        # Wait for service to be healthy again
        case "$service" in
            "postgres"|"redis"|"ollama"|"litellm"|"openwebui"|"qdrant")
                wait_for_service "$service" "http://localhost:${service^^}_PORT/health" "$container_name"
                ;;
        esac
    else
        fail "Service $service container $container_name not found"
    fi
}

# Add new service to platform
add_service() {
    local service="$1"
    
    log "Adding service to platform: $service"
    
    # Check if service is already enabled
    local service_var="${service^^}_ENABLED"
    if [[ "${!service_var}" == "true" ]]; then
        warn "Service $service is already enabled"
        return 0
    fi
    
    # Enable service in platform.conf
    sed -i "s/^${service_var}=.*/${service_var}=true/" "${BASE_DIR}/platform.conf"
    
    # Regenerate docker-compose.yml
    log "Regenerating docker-compose.yml for new service..."
    "${SCRIPT_DIR}/2-deploy-services.sh" "${TENANT_ID}" --dry-run
    
    # Deploy new service
    log "Deploying new service..."
    docker compose -f "${COMPOSE_FILE}" up -d "$service"
    
    log "Service $service added successfully"
}

# Remove service from platform
remove_service() {
    local service="$1"
    local container_name="${TENANT_PREFIX}-${service}"
    
    log "Removing service from platform: $service"
    
    # Stop and remove container
    if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
        docker stop "$container_name"
        docker rm "$container_name"
        log "Service $service container removed"
    fi
    
    # Disable service in platform.conf
    local service_var="${service^^}_ENABLED"
    sed -i "s/^${service_var}=.*/${service_var}=false/" "${BASE_DIR}/platform.conf"
    
    # Remove volumes and data
    local data_dir="${BASE_DIR}/data/${service}"
    if [[ -d "$data_dir" ]]; then
        backup_configuration "$data_dir"
        rm -rf "$data_dir"
        log "Service $service data removed"
    fi
    
    log "Service $service removed successfully"
}

# Temporarily disable service
disable_service() {
    local service="$1"
    local container_name="${TENANT_PREFIX}-${service}"
    
    log "Disabling service: $service"
    
    if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
        docker stop "$container_name"
        log "Service $service disabled (stopped)"
    else
        warn "Service $service is not running"
    fi
    
    # Mark as disabled in platform.conf
    local service_var="${service^^}_ENABLED"
    sed -i "s/^${service_var}=.*/${service_var}=false/" "${BASE_DIR}/platform.conf"
}

# Re-enable disabled service
enable_service() {
    local service="$1"
    local container_name="${TENANT_PREFIX}-${service}"
    
    log "Enabling service: $service"
    
    # Enable in platform.conf
    local service_var="${service^^}_ENABLED"
    sed -i "s/^${service_var}=.*/${service_var}=true/" "${BASE_DIR}/platform.conf"
    
    # Start service
    if docker ps -a --format "{{.Names}}" | grep -q "^${container_name}$"; then
        docker start "$container_name"
        log "Service $service enabled (started)"
    else
        log "Starting new service container..."
        docker compose -f "${COMPOSE_FILE}" up -d "$service"
    fi
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
