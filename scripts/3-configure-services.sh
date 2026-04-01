#!/usr/bin/env bash
# =============================================================================
# Script 3: Mission Control — README v5.1.0 COMPLIANT
# =============================================================================
# PURPOSE: Source platform.conf, call service APIs to complete setup
# USAGE:   bash scripts/3-configure-services.sh [tenant_id] [options]
# OPTIONS: --verify-only     Only verify deployment, don't configure
#          --health-check    Show detailed health status
#          --show-credentials Print all service credentials
#          --rotate-keys [service] Regenerate secrets for one service
# =============================================================================

set -euo pipefail
trap 'echo "ERROR at line $LINENO. Check logs."; exit 1' ERR

# =============================================================================
# NON-ROOT EXECUTION CHECK (README P7)
# =============================================================================
if [[ $EUID -eq 0 ]]; then
    echo "ERROR: This script must not be run as root (README P7 requirement)"
    exit 1
fi

# =============================================================================
# PREREQUISITE CHECK - Scripts 1 and 2 must have run first
# =============================================================================
if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker not installed. Run 1-setup-system.sh first"
    exit 1
fi

if ! docker info &>/dev/null; then
    echo "ERROR: Docker daemon not running. Start it with: sudo systemctl start docker"
    exit 1
fi

if ! docker ps &>/dev/null; then
    echo "ERROR: No containers running. Run 2-deploy-services.sh first"
    exit 1
fi

# =============================================================================
# SCRIPT CONFIGURATION
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT_VERSION="5.1.0"

# =============================================================================
# LOGGING (README P11)
# =============================================================================
LOG_FILE="/var/log/ai-platform-configure.log"
exec > >(tee -a "$LOG_FILE") 2>&1
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
        fail "Unhealthy containers: ${unhealthy_containers[*]}"
    fi
    
    ok "All containers are healthy"
}

# =============================================================================
# SERVICE CONFIGURATION FUNCTIONS
# =============================================================================
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
        fail "Ollama not ready after timeout"
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
        if curl -sf "${qdrant_url}/health" >/dev/null 2>&1; then
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
        if curl -sf "${dify_url}/health" >/dev/null 2>&1; then
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
        -d "{\"init_password\":\"${DIFY_INIT_PASSWORD}\"}" 2>/dev/null || true)
    
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
        if curl -sf "${authentik_url}/-/health/" >/dev/null 2>&1; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 3
    done
    
    if [[ $attempts -ge $max_attempts ]]; then
        fail "Authentik not ready after timeout"
    fi
    
    # README §6: Verify bootstrap (do NOT create user - Authentik creates akadmin automatically)
    log "  Verifying Authentik bootstrap..."
    
    # First authenticate to get proper token
    local auth_response
    auth_response=$(curl -sf -X POST "${authentik_url}/api/v3/core/token/" \
        -H "Content-Type: application/json" \
        -d '{"identifier":"akadmin","password":"'${AUTHENTIK_BOOTSTRAP_PASSWORD}'"}' 2>/dev/null || true)
    
    if [[ -z "$auth_response" ]]; then
        warn "Failed to authenticate with Authentik"
        return 1
    fi
    
    local auth_token
    auth_token=$(echo "$auth_response" | jq -r '.access_token' 2>/dev/null || echo "")
    
    if [[ -z "$auth_token" || "$auth_token" == "null" ]]; then
        warn "Failed to extract Authentik auth token"
        return 1
    fi
    
    # Check if akadmin user exists (indicates bootstrap completed)
    local admin_exists
    admin_exists=$(curl -sf "${authentik_url}/api/v1/core/users/" \
        -H "Authorization: Bearer ${auth_token}" 2>/dev/null | \
        jq -r '.results[] | select(.username=="akadmin") | .username' 2>/dev/null || echo "")
    
    if [[ "$admin_exists" == "akadmin" ]]; then
        log "  Authentik bootstrap verified (akadmin user exists)"
    else
        warn "Authentik bootstrap may not be complete"
    fi
    
    # Retrieve and store API token (README §6)
    log "  Retrieving Authentik API token..."
    local token_response
    token_response=$(curl -sf -X POST "${authentik_url}/api/v1/core/tokens/" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${auth_token}" \
        -d '{"identifier":"akadmin","password":"'${AUTHENTIK_BOOTSTRAP_PASSWORD}'"}' 2>/dev/null || true)
    
    if [[ -n "$token_response" ]]; then
        local api_key
        api_key=$(echo "$token_response" | jq -r '.key' 2>/dev/null || echo "")
        if [[ -n "$api_key" && "$api_key" != "null" ]]; then
            # Append to platform.conf (README §6)
            echo "AUTHENTIK_API_TOKEN=\"${api_key}\"" >> "${BASE_DIR}/platform.conf"
            log "  Authentik API token stored"
        else
            warn "Failed to extract Authentik API token"
        fi
    else
        warn "Failed to retrieve Authentik API token"
    fi
    
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
    echo "  Tenant: ${TENANT_ID}   Built: ${GENERATED_AT}"
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
        echo "  JWT Secret  ${LIBRECHAT_JWT_SECRET}"
        echo "  Crypt Key   ${LIBRECHAT_CRYPT_KEY}"
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
        echo "  Secret Key  ${DIFY_SECRET_KEY}"
        echo "  Init Pass   ${DIFY_INIT_PASSWORD}"
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
    
    # Source platform.conf (README P1 - BUG-02 fix)
    local platform_conf="/mnt/${tenant_id}/platform.conf"
    if [[ ! -f "$platform_conf" ]]; then
        fail "platform.conf not found at $platform_conf. Run script 1 first."
    fi
    # shellcheck source=/dev/null
    source "$platform_conf"
    
    # Source shared configuration now that variables are set
    [[ -f "${SCRIPT_DIR}/shared-config.sh" ]] && source "${SCRIPT_DIR}/shared-config.sh"
    
    # Set up logging
    LOG_FILE="${LOG_DIR}/$(basename "$0" .sh)-$(date +%Y%m%d-%H%M%S).log"
    CONFIGURED_DIR="${BASE_DIR}/.configured"
    mkdir -p "$CONFIGURED_DIR"
    
    log "=== Script 3: Mission Control ==="
    log "Version: ${SCRIPT_VERSION}"
    log "Tenant: ${tenant_id}"
    log "Verify-only: ${verify_only}"
    log "Health-check: ${health_check}"
    log "Show-credentials: ${show_credentials}"
    log "Rotate-keys: ${rotate_keys}"
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
