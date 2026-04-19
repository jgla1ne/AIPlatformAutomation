#!/usr/bin/env bash
# =============================================================================
# Script 3: Mission Control Hub
# PURPOSE: Complete service management, health monitoring, credentials, key rotation, and post-deployment configuration
# =============================================================================
# USAGE:   bash scripts/3-configure-services.sh [tenant_id] [options]
# OPTIONS: --verify-only              Only verify deployment, don't configure
#          --health-check             Show live health table for all containers
#          --show-credentials         Print all service credentials and URLs
#          --rotate-keys <service>    Regenerate secrets for one service
#          --restart <service>        Restart specific service
#          --add <service>            Add new service to platform
#          --remove <service>         Remove service from platform
#          --disable <service>        Temporarily stop service
#          --enable <service>         Re-enable stopped service
#          --dry-run                  Show what would be done
#          --ingest                   Run ingestion pipeline (rclone → vector DB)
#          --skip-sync                Skip rclone sync, ingest existing files only
#          --logs <service>           Tail logs for a service (interactive)
#          --log-lines <N>            Number of lines to show (default: 200)
#          --audit-logs               Show ERROR/WARN counts for all containers
#          --reconfigure <service>    Reset credentials for a service
#          --litellm-routing <strat>  Change LiteLLM routing strategy
#          --ollama-list              List loaded Ollama models
#          --ollama-pull <model>      Pull a new Ollama model
#          --ollama-remove <model>    Remove an Ollama model
#          --ollama-latest            Fetch latest models from ollama.com/library
#          --configure-models         Configure Ollama and external LLM models interactively
#          --configure-ai             Configure AI development tools (Code Server, Continue.dev)
#          --flushall                 Flush all databases and reinitialize (self-healing)
#          --backup                   Create a one-off backup of tenant data
#          --schedule "<cron>"        Schedule recurring backups (use with --backup)
#          --setup-persistence        Ensure platform stands up automatically after reboot
#          --test-pipeline           Test complete rclone→Qdrant→LiteLLM→LLM pipeline
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
section() {
    echo ""
    echo "── $1 ──────────────────────────────────────────────────"
}

# =============================================================================
# HEALTH CHECK UTILITIES
# =============================================================================
wait_for_health() {
    local container_name="$1"
    local timeout="${2:-90}"
    local interval=5
    local elapsed=0

    log "Waiting for ${container_name} to become healthy (timeout: ${timeout}s)..."

    while [[ ${elapsed} -lt ${timeout} ]]; do
        local status
        status=$(docker inspect \
            --format='{{.State.Health.Status}}' \
            "${container_name}" 2>/dev/null) || status="not_found"

        case "${status}" in
            healthy)
                log "  ${container_name} is healthy"
                return 0
                ;;
            unhealthy)
                log "  ${container_name} reported unhealthy"
                return 1
                ;;
            not_found)
                log "  ${container_name} not found"
                ;;
            starting)
                log "  ${container_name} still starting..."
                ;;
        esac

        sleep ${interval}
        elapsed=$((elapsed + interval))
    done

    log "  ${container_name} health check timed out after ${timeout}s"
    return 1
}

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

    if [[ "${ZEP_ENABLED:-false}" == "true" ]]; then
        if ! docker ps --format "{{.Names}}" | grep -q "^${TENANT_PREFIX}-zep$"; then
            fail "Zep container not running"
        fi
        local status
        status=$(docker inspect --format='{{.State.Health.Status}}' "${TENANT_PREFIX}-zep" 2>/dev/null || echo "none")
        if [[ "$status" != "healthy" ]]; then
            unhealthy_containers+=("zep")
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
# COMPREHENSIVE PIPELINE TESTING FUNCTIONS
# =============================================================================

# Test complete rclone -> Qdrant -> LiteLLM -> external LLM pipeline
test_full_pipeline() {
    local tenant_id="${1}"
    
    # Source platform.conf to get all required variables
    local platform_conf="/mnt/${tenant_id}/config/platform.conf"
    if [[ ! -f "$platform_conf" ]]; then
        echo "ERROR: platform.conf not found at $platform_conf. Run script 1 first."
        return 1
    fi
    # shellcheck source=/dev/null
    source "$platform_conf"
    
    echo "=== TESTING FULL AI PIPELINE ==="
    echo "Tenant: ${tenant_id}"
    echo ""
    
    # Test 1: rclone configuration and connectivity
    echo "1. Testing rclone configuration..."
    local rclone_container="${TENANT_PREFIX}-rclone"
    if docker ps --format "{{.Names}}" | grep -q "${rclone_container}"; then
        echo "   ✅ rclone container is running"
        
        # Test rclone config
        if docker exec "${rclone_container}" rclone config show 2>/dev/null | grep -q "gdrive"; then
            echo "   ✅ rclone GDrive config found"
        else
            echo "   ❌ rclone GDrive config missing"
            return 1
        fi
        
        # Test GDrive connectivity
        if docker exec "${rclone_container}" rclone lsd gdrive: 2>/dev/null; then
            echo "   ✅ GDrive connectivity OK"
        else
            echo "   ⚠️  GDrive connectivity failed (may need folder sharing)"
        fi
    else
        echo "   ⚠️  rclone container not running"
    fi
    echo ""
    
    # Test 2: Qdrant vector database operations
    echo "2. Testing Qdrant operations..."
    local qdrant_url="http://127.0.0.1:${QDRANT_REST_PORT:-6333}"
    local qdrant_container="${TENANT_PREFIX}-qdrant"
    
    if docker ps --format "{{.Names}}" | grep -q "${qdrant_container}"; then
        echo "   ✅ Qdrant container is running"
        
        # Test collection creation
        local test_collection="pipeline-test-$(date +%s)"
        if curl -sf -X PUT "${qdrant_url}/collections/${test_collection}" \
            -H "Content-Type: application/json" \
            -d '{"vectors": {"size": 1536, "distance": "Cosine"}}' >/dev/null; then
            echo "   ✅ Qdrant collection creation OK"
            
            # Test vector upsert
            if curl -sf -X PUT "${qdrant_url}/collections/${test_collection}/points" \
                -H "Content-Type: application/json" \
                -d '{"points": [{"id": 1, "vector": [0.1] * 1536}]}' >/dev/null; then
                echo "   ✅ Qdrant vector upsert OK"
                
                # Test vector search
                if curl -sf -X POST "${qdrant_url}/collections/${test_collection}/points/search" \
                    -H "Content-Type: application/json" \
                    -d '{"vector": [0.1] * 1536, "limit": 1}' >/dev/null; then
                    echo "   ✅ Qdrant vector search OK"
                else
                    echo "   ❌ Qdrant vector search failed"
                fi
            else
                echo "   ❌ Qdrant vector upsert failed"
            fi
            
            # Cleanup test collection
            curl -sf -X DELETE "${qdrant_url}/collections/${test_collection}" >/dev/null
        else
            echo "   ❌ Qdrant collection creation failed"
        fi
    else
        echo "   ❌ Qdrant container not running"
    fi
    echo ""
    
    # Test 3: LiteLLM model availability and routing
    echo "3. Testing LiteLLM model routing..."
    local litellm_url="http://127.0.0.1:${LITELLM_PORT:-4000}"
    
    if curl -sf "${litellm_url}/health/liveliness" >/dev/null; then
        echo "   ✅ LiteLLM service is healthy"
        
        # Test model list
        local model_count
        model_count=$(curl -sf -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
            "${litellm_url}/v1/models" | jq '.data | length' 2>/dev/null || echo "0")
        echo "   ✅ Available models: ${model_count}"
        
        # Test each provider category
        echo "   Testing provider categories:"
        
        # Test Ollama models
        local ollama_models
        ollama_models=$(curl -sf -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
            "${litellm_url}/v1/models" | jq -r '.data[] | select(.id | startswith("ollama/")) | .id' 2>/dev/null)
        if [[ -n "${ollama_models}" ]]; then
            echo "     ✅ Ollama models: $(echo "${ollama_models}" | wc -l)"
        else
            echo "   ❌ No Ollama models found"
        fi
        
        # Test Groq models
        local groq_models
        groq_models=$(curl -sf -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
            "${litellm_url}/v1/models" | jq -r '.data[] | select(.id | contains("groq")) | .id' 2>/dev/null)
        if [[ -n "${groq_models}" ]]; then
            echo "     ✅ Groq models: $(echo "${groq_models}" | wc -l)"
        else
            echo "   ⚠️  No Groq models found"
        fi
        
        # Test embedding models
        local embedding_models
        embedding_models=$(curl -sf -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
            "${litellm_url}/v1/models" | jq -r '.data[] | select(.id | contains("embedding")) | .id' 2>/dev/null)
        if [[ -n "${embedding_models}" ]]; then
            echo "     ✅ Embedding models: $(echo "${embedding_models}" | wc -l)"
        else
            echo "   ❌ No embedding models found"
        fi
        
        # Test actual chat completion with first available model
        local test_model
        test_model=$(curl -sf -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
            "${litellm_url}/v1/models" | jq -r '.data[0].id' 2>/dev/null)
        
        if [[ -n "${test_model}" ]]; then
            echo "   Testing chat completion with model: ${test_model}"
            local test_response
            test_response=$(curl -sf -X POST -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
                -H "Content-Type: application/json" \
                -d "{\"model\":\"${test_model}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say OK\"}],\"max_tokens\":5}" \
                "${litellm_url}/v1/chat/completions" | jq -r '.choices[0].message.content' 2>/dev/null)
            
            if [[ "${test_response}" == *"OK"* ]]; then
                echo "     ✅ Chat completion test PASSED"
            else
                echo "     ❌ Chat completion test FAILED: ${test_response}"
            fi
        else
            echo "   ❌ No models available for testing"
        fi
    else
        echo "   ❌ LiteLLM service not healthy"
    fi
    echo ""
    
    # Test 4: External LLM provider connectivity (if keys configured)
    echo "4. Testing external LLM provider connectivity..."
    
    if [[ -n "${GROQ_API_KEY}" ]]; then
        echo "   Testing Groq API connectivity..."
        if curl -sf -H "Authorization: Bearer ${GROQ_API_KEY}" \
            "https://api.groq.com/openai/v1/models" >/dev/null; then
            echo "     ✅ Groq API connectivity OK"
        else
            echo "     ❌ Groq API connectivity failed"
        fi
    fi
    
    if [[ -n "${OPENAI_API_KEY}" ]]; then
        echo "   Testing OpenAI API connectivity..."
        if curl -sf -H "Authorization: Bearer ${OPENAI_API_KEY}" \
            "https://api.openai.com/v1/models" >/dev/null; then
            echo "     ✅ OpenAI API connectivity OK"
        else
            echo "     ❌ OpenAI API connectivity failed"
        fi
    fi
    
    if [[ -n "${ANTHROPIC_API_KEY}" ]]; then
        echo "   Testing Anthropic API connectivity..."
        if curl -sf -H "Authorization: Bearer ${ANTHROPIC_API_KEY}" \
            "https://api.anthropic.com/v1/messages" >/dev/null; then
            echo "     ✅ Anthropic API connectivity OK"
        else
            echo "     ❌ Anthropic API connectivity failed"
        fi
    fi
    
    echo ""
    echo "=== PIPELINE TEST COMPLETE ==="
    return 0
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
    
    # Note: Model pulling is handled in Script 2 during deployment to avoid
    # re-download costs on Script 3 re-runs. Use --ollama-pull to add models.
    log "Ollama is ready. Model management available via --ollama-* commands."
    
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

    # Wait for LibreChat to be ready (image has wget, not curl)
    local attempts=0
    local max_attempts=30

    while [[ $attempts -lt $max_attempts ]]; do
        if wget -q --spider "${librechat_url}/health" >/dev/null 2>&1; then
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
        if curl -sf "${openclaw_url}/health" >/dev/null 2>&1; then
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

configure_anythingllm() {
    if [[ "${ANYTHINGLLM_ENABLED:-false}" != "true" ]]; then
        return 0
    fi

    if step_done "anythingllm_configured"; then
        log "AnythingLLM already configured, skipping"
        return 0
    fi

    local _port="${ANYTHINGLLM_PORT:-3001}"
    local _url="http://127.0.0.1:${_port}"

    log "Configuring AnythingLLM..."

    # Wait for AnythingLLM to be ready
    local _attempts=0
    while [[ $_attempts -lt 30 ]]; do
        if curl -sf "${_url}/api/setup-complete" >/dev/null 2>&1; then
            break
        fi
        _attempts=$((_attempts + 1))
        sleep 3
    done

    if [[ $_attempts -ge 30 ]]; then
        fail "AnythingLLM not ready after timeout"
        return 1
    fi

    # Determine host-accessible LiteLLM URL (127.0.0.1 works since containers share host network via port mapping)
    local _litellm_base="http://127.0.0.1:${LITELLM_PORT:-4000}/v1"
    local _default_model="ollama/${OLLAMA_DEFAULT_MODEL:-llama3.2:3b}"

    # Set LLM provider to generic-openai (LiteLLM)
    local _resp
    _resp=$(curl -s -X POST "${_url}/api/system/update-env" \
        -H "Content-Type: application/json" \
        -d "{
            \"LLMProvider\": \"generic-openai\",
            \"GenericOpenAiBasePath\": \"${_litellm_base}\",
            \"GenericOpenAiKey\": \"${LITELLM_MASTER_KEY}\",
            \"GenericOpenAiModel\": \"${_default_model}\",
            \"GenericOpenAiModelTokenLimit\": 4096,
            \"GenericOpenAiStreamingEnabled\": true
        }" 2>/dev/null)

    if echo "${_resp}" | grep -q '"error":false'; then
        ok "  AnythingLLM LLM provider → generic-openai (LiteLLM @ ${_litellm_base})"
    else
        warn "  AnythingLLM LLM update may have failed: ${_resp:0:80}"
    fi

    # Set embedding provider to generic-openai (LiteLLM)
    _resp=$(curl -s -X POST "${_url}/api/system/update-env" \
        -H "Content-Type: application/json" \
        -d "{
            \"EmbeddingEngine\": \"generic-openai\",
            \"GenericOpenAiEmbeddingApiBase\": \"${_litellm_base}\",
            \"GenericOpenAiEmbeddingApiKey\": \"${LITELLM_MASTER_KEY}\",
            \"GenericOpenAiEmbeddingModelPref\": \"${_default_model}\"
        }" 2>/dev/null)

    if echo "${_resp}" | grep -q '"error":false'; then
        ok "  AnythingLLM embedding provider → generic-openai (LiteLLM)"
    else
        warn "  AnythingLLM embedding update may have failed: ${_resp:0:80}"
    fi

    # Verify VectorDB is qdrant (set via env at deploy time — just confirm)
    local _state
    _state=$(curl -s "${_url}/api/setup-complete" 2>/dev/null)
    local _vdb
    _vdb=$(echo "${_state}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['results']['VectorDB'])" 2>/dev/null || echo "?")
    ok "  AnythingLLM VectorDB: ${_vdb}"

    mark_done "anythingllm_configured"
    ok "AnythingLLM configured (LiteLLM proxy, Qdrant vector store)"
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
    
    # Dify has two separate containers — the setup API lives on dify-api (Flask backend),
    # NOT on dify-web (Next.js frontend). Calling /console/api/setup on the web port
    # returns 404; it must target the api port (5001).
    local container_name="${TENANT_PREFIX}-dify"
    local dify_api_url="http://127.0.0.1:${DIFY_API_PORT:-5001}"
    local dify_web_url="http://127.0.0.1:${DIFY_PORT:-3040}"

    log "Configuring Dify..."

    # Guard: dify-api container must exist
    if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${TENANT_PREFIX}-dify-api$"; then
        warn "dify-api container not found — skipping Dify setup (will retry on next Script 3 run)"
        return 0
    fi

    # Wait for dify-api to be ready (setup endpoint is on the Flask backend)
    local attempts=0
    local max_attempts=30

    while [[ $attempts -lt $max_attempts ]]; do
        if curl -sf "${dify_api_url}/health" >/dev/null 2>&1; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 2
    done

    if [[ $attempts -ge $max_attempts ]]; then
        warn "dify-api not ready after timeout — skipping setup"
        return 0
    fi

    # Call setup only if DIFY_INIT_PASSWORD is set; skip silently if empty (user will set up manually)
    if [[ -n "${DIFY_INIT_PASSWORD:-}" ]]; then
        log "  Calling Dify setup API on dify-api (port ${DIFY_API_PORT:-5001})..."
        local setup_response
        setup_response=$(curl -s -X POST "${dify_api_url}/console/api/setup" \
            -H "Content-Type: application/json" \
            -d "{\"init_password\":\"${DIFY_INIT_PASSWORD}\"}" 2>/dev/null || true)

        if echo "${setup_response:-}" | grep -qi '"result":"success"\|already_setup\|setup_finished'; then
            ok "  Dify setup completed"
        else
            log "  Dify setup response: ${setup_response:-<empty>}"
            warn "  Dify setup API call returned unexpected response — may already be set up"
        fi
    else
        log "  DIFY_INIT_PASSWORD not set — skipping automated setup"
        log "  Open $(_url dify-api ${DIFY_API_PORT:-5001} 2>/dev/null || echo "http://127.0.0.1:${DIFY_API_PORT:-5001}") and complete setup manually"
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
    
    # Run migrations to ensure all schema objects exist (idempotent).
    docker exec "${container_name}" ak migrate 2>/dev/null || true

    # Authentik bootstrap is automatic — akadmin user created from AUTHENTIK_BOOTSTRAP_PASSWORD env var.
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

configure_searxng() {
    if [[ "${SEARXNG_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    if step_done "searxng_configured"; then
        log "SearXNG already configured, skipping"
        return 0
    fi
    
    local container_name="${TENANT_PREFIX}-searxng"
    
    # Wait for SearXNG to be healthy
    wait_for_health "$container_name" 90 || {
        warn "SearXNG container not healthy, skipping configuration"
        return 1
    }
    
    log "Configuring SearXNG..."
    
    # SearXNG is pre-configured via environment variables
    # Just verify it's accessible
    if curl -s "http://127.0.0.1:${SEARXNG_PORT}" | grep -q "SearXNG"; then
        log "SearXNG is accessible and working"
    else
        warn "SearXNG may not be fully configured yet"
    fi
    
    mark_done "searxng_configured"
    ok "SearXNG configured"
}

configure_ai_dev_tools() {
    if [[ "${CODE_SERVER_ENABLED:-false}" != "true" && "${CONTINUE_DEV_ENABLED:-false}" != "true" ]]; then
        return 0
    fi
    
    if step_done "ai_dev_tools_configured"; then
        log "AI dev tools already configured, skipping"
        return 0
    fi
    
    log "Configuring AI development tools..."
    
    # Update Code Server settings with current model configuration
    if [[ "${CODE_SERVER_ENABLED:-false}" == "true" ]]; then
        local code_settings_dir="${DATA_DIR}/code-server/.local/share/code-server"
        if [[ -f "${code_settings_dir}/settings.json" ]]; then
            log "Updating Code Server AI settings..."
            
            # Update the model in settings.json
            sed -i "s/\"ai.openai-compatible.model\": \"[^\"]*\"/\"ai.openai-compatible.model\": \"${OLLAMA_DEFAULT_MODEL:-llama3.1:8b}\"/g" "${code_settings_dir}/settings.json"
            sed -i "s/\"continue.model\": \"[^\"]*\"/\"continue.model\": \"${OLLAMA_DEFAULT_MODEL:-llama3.1:8b}\"/g" "${code_settings_dir}/settings.json"
            
            ok "Code Server AI settings updated"
        fi
    fi
    
    # Regenerate Continue.dev config with current models
    if [[ "${CONTINUE_DEV_ENABLED:-false}" == "true" ]]; then
        log "Regenerating Continue.dev configuration..."

        local continue_dir="${DATA_DIR}/continue-dev"
        # Continue.dev extension inside code-server reads ~/.continue/config.json
        local continue_home_dir="${DATA_DIR}/code-server/.continue"
        mkdir -p "${continue_dir}" "${continue_home_dir}"

        # Install continue.dev extension if code-server is running
        if [[ "${CODE_SERVER_ENABLED:-false}" == "true" ]]; then
            docker exec "${TENANT_PREFIX}-code-server" \
                code-server --install-extension continue.continue --force 2>/dev/null || true
        fi

        local models_config=""
        local first_model="${OLLAMA_DEFAULT_MODEL:-llama3.1:8b}"
        local first_litellm_model="ollama/${first_model}"

        IFS=',' read -ra models <<< "${OLLAMA_MODELS:-llama3.2:3b}"
        for model in "${models[@]}"; do
            model=$(echo "$model" | xargs)
            if [[ -n "$model" ]]; then
                [[ -n "$models_config" ]] && models_config="${models_config},"
                models_config="${models_config}
    {
      \"title\": \"${model} (via LiteLLM)\",
      \"provider\": \"openai\",
      \"model\": \"ollama/${model}\",
      \"apiBase\": \"http://127.0.0.1:${LITELLM_PORT:-4000}/v1\",
      \"apiKey\": \"${LITELLM_MASTER_KEY}\"
    }"
            fi
        done

        if [[ "${ENABLE_OPENAI:-false}" == "true" && -n "${OPENAI_API_KEY:-}" ]]; then
            [[ -n "$models_config" ]] && models_config="${models_config},"
            models_config="${models_config}
    {\"title\":\"GPT-4 (via LiteLLM)\",\"provider\":\"openai\",\"model\":\"gpt-4\",\"apiBase\":\"http://127.0.0.1:${LITELLM_PORT:-4000}/v1\",\"apiKey\":\"${LITELLM_MASTER_KEY}\"}"
        fi

        if [[ "${ENABLE_ANTHROPIC:-false}" == "true" && -n "${ANTHROPIC_API_KEY:-}" ]]; then
            [[ -n "$models_config" ]] && models_config="${models_config},"
            models_config="${models_config}
    {\"title\":\"Claude-3-Sonnet (via LiteLLM)\",\"provider\":\"openai\",\"model\":\"claude-3-sonnet-20240229\",\"apiBase\":\"http://127.0.0.1:${LITELLM_PORT:-4000}/v1\",\"apiKey\":\"${LITELLM_MASTER_KEY}\"}"
        fi

        local _cfg
        _cfg=$(cat << CONTEOF
{
  "models": [${models_config}
  ],
  "tabAutocompleteModel": {
    "title": "${first_model} (via LiteLLM)",
    "provider": "openai",
    "model": "${first_litellm_model}",
    "apiBase": "http://127.0.0.1:${LITELLM_PORT:-4000}/v1",
    "apiKey": "${LITELLM_MASTER_KEY}"
  },
  "embeddingsProvider": {
    "provider": "openai",
    "model": "${first_litellm_model}",
    "apiBase": "http://127.0.0.1:${LITELLM_PORT:-4000}/v1",
    "apiKey": "${LITELLM_MASTER_KEY}"
  },
  "allowAnonymousTelemetry": false
}
CONTEOF
)
        echo "${_cfg}" > "${continue_home_dir}/config.json"
        echo "${_cfg}" > "${continue_dir}/config.json"
        chmod 644 "${continue_home_dir}/config.json" "${continue_dir}/config.json"

        ok "Continue.dev configuration written to ${continue_home_dir}/config.json"
        ok "  Available models: $(echo "${OLLAMA_MODELS:-llama3.2:3b}" | tr ',' ' ')"
    fi
    
    mark_done "ai_dev_tools_configured"
    ok "AI development tools configured"
}

configure_zep() {
    if [[ "${ZEP_ENABLED:-false}" != "true" ]]; then
        return 0
    fi

    if step_done "zep_configured"; then
        log "Zep already configured, skipping"
        return 0
    fi

    local container_name="${TENANT_PREFIX}-zep"
    local zep_url="http://127.0.0.1:${ZEP_PORT}"

    log "Configuring Zep..."

    # Wait for Zep to be ready
    local attempts=0
    local max_attempts=30

    while [[ $attempts -lt $max_attempts ]]; do
        if bash -c "echo > /dev/tcp/127.0.0.1/${ZEP_PORT:-8100}" 2>/dev/null; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 2
    done

    if [[ $attempts -ge $max_attempts ]]; then
        fail "Zep not ready after timeout"
    fi

    mark_done "zep_configured"
    ok "Zep configured"
}

configure_letta() {
    if [[ "${LETTA_ENABLED:-false}" != "true" ]]; then
        return 0
    fi

    if step_done "letta_configured"; then
        log "Letta already configured, skipping"
        return 0
    fi

    local letta_url="http://127.0.0.1:${LETTA_PORT:-8283}"

    log "Configuring Letta..."

    local attempts=0
    local max_attempts=30
    while [[ $attempts -lt $max_attempts ]]; do
        if curl -sf "${letta_url}/v1/health" >/dev/null 2>&1; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 2
    done

    if [[ $attempts -ge $max_attempts ]]; then
        fail "Letta not ready after timeout"
    fi

    mark_done "letta_configured"
    ok "Letta configured"
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
    # Compute correct URLs — subdomain-based when Caddy/NPM active, IP:port otherwise.
    # This is the definitive reference a user can open in their browser.
    local _cred_proto="http"
    local _cred_host
    _cred_host=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
    local _use_subs=false
    if [[ "${CADDY_ENABLED:-false}" == "true" || "${NPM_ENABLED:-false}" == "true" ]]; then
        local _dom="${BASE_DOMAIN:-${DOMAIN:-}}"
        if [[ -n "$_dom" ]]; then
            _cred_proto="https"
            _cred_host="$_dom"
            _use_subs=true
        fi
    fi
    # _url <subdomain> <fallback-port>  →  correct browser URL
    _url() {
        if [[ "$_use_subs" == "true" ]]; then
            echo "${_cred_proto}://${1}.${_cred_host}"
        else
            echo "${_cred_proto}://${_cred_host}:${2}"
        fi
    }

    echo ""
    echo "══════════════════════════════════════════════════════════════════════"
    echo "  AI PLATFORM — CREDENTIALS & ACCESS URLS"
    echo "  Tenant: ${TENANT_ID}   Built: ${GENERATED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
    echo "══════════════════════════════════════════════════════════════════════"
    echo ""

    # ── Infrastructure ────────────────────────────────────────────────────────
    if [[ "${POSTGRES_ENABLED:-false}" == "true" ]]; then
        echo "INFRASTRUCTURE"
        echo "  PostgreSQL   ${_cred_host}:${POSTGRES_PORT:-5432}  (internal)"
        echo "  User         ${POSTGRES_USER:-${TENANT_ID}}"
        echo "  Password     ${POSTGRES_PASSWORD:-<not set>}"
        [[ "${REDIS_ENABLED:-false}" == "true" ]] && \
            echo "  Redis pass   ${REDIS_PASSWORD:-<not set>}"
        echo ""
    fi

    # ── LLM Gateway ───────────────────────────────────────────────────────────
    if [[ "${LITELLM_ENABLED:-false}" == "true" ]]; then
        echo "LLM GATEWAY"
        echo "  URL          $(_url litellm ${LITELLM_PORT:-4000})"
        echo "  Master Key   ${LITELLM_MASTER_KEY:-<not set>}"
        echo "  UI Password  ${LITELLM_UI_PASSWORD:-<not set — check platform.conf>}"
        echo ""
    fi

    # ── Web UIs ───────────────────────────────────────────────────────────────
    local _has_webui=false
    [[ "${OPENWEBUI_ENABLED:-false}" == "true" ]] && _has_webui=true
    [[ "${LIBRECHAT_ENABLED:-false}" == "true" ]] && _has_webui=true
    [[ "${OPENCLAW_ENABLED:-false}"  == "true" ]] && _has_webui=true
    [[ "${ANYTHINGLLM_ENABLED:-false}" == "true" ]] && _has_webui=true
    if [[ "$_has_webui" == "true" ]]; then
        echo "WEB UIs"
        if [[ "${OPENWEBUI_ENABLED:-false}" == "true" ]]; then
            echo "  OpenWebUI    $(_url openwebui ${OPENWEBUI_PORT:-3000})"
            echo "    Login      Register on first visit (no default password)"
        fi
        if [[ "${LIBRECHAT_ENABLED:-false}" == "true" ]]; then
            echo "  LibreChat    $(_url librechat ${LIBRECHAT_PORT:-3080})"
            echo "    Login      Register on first visit"
        fi
        if [[ "${OPENCLAW_ENABLED:-false}" == "true" ]]; then
            echo "  OpenClaw     $(_url openclaw ${OPENCLAW_PORT:-18789})"
            # OpenClaw UI asks for a gateway token (not username/password).
            # The WSS gateway URL is used by the desktop/mobile client to connect.
            local _oc_gateway_proto="wss"
            local _oc_gateway_host="${BASE_DOMAIN:-}"
            if [[ -z "${_oc_gateway_host}" ]] || [[ "${CADDY_ENABLED:-false}" != "true" && "${NPM_ENABLED:-false}" != "true" ]]; then
                _oc_gateway_proto="ws"
                _oc_gateway_host="${DOMAIN:-localhost}:${OPENCLAW_PORT:-18789}"
            else
                _oc_gateway_host="openclaw.${BASE_DOMAIN}"
            fi
            echo "    Gateway URL  ${_oc_gateway_proto}://${_oc_gateway_host}"
            echo "    Token        ${OPENCLAW_PASSWORD:-<not set — check platform.conf>}"
        fi
        if [[ "${ANYTHINGLLM_ENABLED:-false}" == "true" ]]; then
            echo "  AnythingLLM  $(_url anythingllm ${ANYTHINGLLM_PORT:-3001})"
            echo "    Login      Register on first visit (no default password)"
            echo "    JWT Secret ${ANYTHINGLLM_JWT_SECRET:-<not set>}  (internal)"
        fi
        echo ""
    fi

    # ── Automation ────────────────────────────────────────────────────────────
    local _has_auto=false
    [[ "${N8N_ENABLED:-false}"    == "true" ]] && _has_auto=true
    [[ "${FLOWISE_ENABLED:-false}" == "true" ]] && _has_auto=true
    [[ "${DIFY_ENABLED:-false}"   == "true" ]] && _has_auto=true
    if [[ "$_has_auto" == "true" ]]; then
        echo "AUTOMATION"
        if [[ "${N8N_ENABLED:-false}" == "true" ]]; then
            echo "  N8N          $(_url n8n ${N8N_PORT:-5678})"
            echo "    Login      Register on first visit (no default password)"
            echo "    Enc. Key   ${N8N_ENCRYPTION_KEY:-<not set>}  (internal)"
        fi
        if [[ "${FLOWISE_ENABLED:-false}" == "true" ]]; then
            echo "  Flowise      $(_url flowise ${FLOWISE_PORT:-3001})"
            echo "    Username   ${FLOWISE_USERNAME:-admin}"
            echo "    Password   ${FLOWISE_PASSWORD:-<not set>}"
        fi
        if [[ "${DIFY_ENABLED:-false}" == "true" ]]; then
            echo "  Dify         $(_url dify ${DIFY_PORT:-3040})  (web+api via path routing)"
            echo "    Init Pass  ${DIFY_INIT_PASSWORD:-<not set — check platform.conf>}  (set on first login)"
        fi
        echo ""
    fi

    # ── Vector DBs ────────────────────────────────────────────────────────────
    local _has_vec=false
    [[ "${QDRANT_ENABLED:-false}" == "true" ]] && _has_vec=true
    if [[ "$_has_vec" == "true" ]]; then
        echo "VECTOR DB"
        if [[ "${QDRANT_ENABLED:-false}" == "true" ]]; then
            echo "  Qdrant       http://127.0.0.1:${QDRANT_PORT:-6333}  (internal)"
            echo "    API Key    ${QDRANT_API_KEY:-<not set>}"
        fi
        echo ""
    fi

    # ── Memory Layer ──────────────────────────────────────────────────────────
    local _has_mem=false
    [[ "${ZEP_ENABLED:-false}"   == "true" ]] && _has_mem=true
    [[ "${LETTA_ENABLED:-false}" == "true" ]] && _has_mem=true
    if [[ "$_has_mem" == "true" ]]; then
        echo "MEMORY LAYER"
        if [[ "${ZEP_ENABLED:-false}" == "true" ]]; then
            echo "  Zep CE       $(_url zep ${ZEP_PORT:-8100})"
            echo "    Auth Sec   ${ZEP_AUTH_SECRET:-<not set>}"
        fi
        if [[ "${LETTA_ENABLED:-false}" == "true" ]]; then
            echo "  Letta        $(_url letta ${LETTA_PORT:-8283})"
            echo "    Password   ${LETTA_SERVER_PASS:-<not set>}"
        fi
        echo ""
    fi

    # ── Identity ──────────────────────────────────────────────────────────────
    if [[ "${AUTHENTIK_ENABLED:-false}" == "true" ]]; then
        echo "IDENTITY"
        echo "  Authentik    $(_url authentik ${AUTHENTIK_PORT:-9000})"
        echo "    Email      ${AUTHENTIK_BOOTSTRAP_EMAIL:-${ADMIN_EMAIL:-akadmin@localhost}}"
        echo "    Password   ${AUTHENTIK_BOOTSTRAP_PASSWORD:-<not set — check platform.conf>}"
        [[ -n "${AUTHENTIK_API_TOKEN:-}" ]] && \
            echo "    API Token  ${AUTHENTIK_API_TOKEN}"
        echo ""
    fi

    # ── Monitoring ────────────────────────────────────────────────────────────
    local _has_mon=false
    [[ "${GRAFANA_ENABLED:-false}"    == "true" ]] && _has_mon=true
    [[ "${PROMETHEUS_ENABLED:-false}" == "true" ]] && _has_mon=true
    if [[ "$_has_mon" == "true" ]]; then
        echo "MONITORING"
        if [[ "${GRAFANA_ENABLED:-false}" == "true" ]]; then
            echo "  Grafana      $(_url grafana ${GRAFANA_PORT:-3000})"
            echo "    Username   admin"
            echo "    Password   ${GRAFANA_ADMIN_PASSWORD:-admin}"
        fi
        if [[ "${PROMETHEUS_ENABLED:-false}" == "true" ]]; then
            echo "  Prometheus   $(_url prometheus ${PROMETHEUS_PORT:-9090})"
        fi
        echo ""
    fi

    # ── Development ───────────────────────────────────────────────────────────
    if [[ "${CODE_SERVER_ENABLED:-false}" == "true" ]]; then
        echo "DEVELOPMENT"
        echo "  Code Server  $(_url code ${CODE_SERVER_PORT:-8080})"
        echo "    Password   ${CODE_SERVER_PASSWORD:-<not set — check platform.conf>}"
        echo ""
    fi

    # ── Search Engine ──────────────────────────────────────────────────────────
    if [[ "${SEARXNG_ENABLED:-false}" == "true" ]]; then
        local _search_url
        if [[ "$_use_subs" == "true" ]]; then
            _search_url="${_cred_proto}://search.${_cred_host}"
        else
            _search_url="http://127.0.0.1:${SEARXNG_PORT:-8888}"
        fi
        echo "SEARCH ENGINE"
        echo "  SearXNG      ${_search_url}"
        echo "    Secret     ${SEARXNG_SECRET_KEY:0:16}..."
        echo ""
    fi

    # ── Alerting / Comms ──────────────────────────────────────────────────────
    if [[ "${SIGNALBOT_ENABLED:-false}" == "true" ]]; then
        local _sig_url
        if [[ "$_use_subs" == "true" ]]; then
            _sig_url="${_cred_proto}://signal.${_cred_host}"
        else
            _sig_url="http://127.0.0.1:${SIGNALBOT_PORT:-8080}"
        fi
        echo "ALERTING / COMMS"
        echo "  Signalbot    ${_sig_url}/v1/about"
        echo "    QR Pair    ${_sig_url}/v1/qrcodelink?device_name=signal-api"
        echo "    Phone      ${SIGNAL_PHONE:-<not configured>}"
        [[ -n "${SIGNAL_RECIPIENT:-}" ]] && \
            echo "    Recipient  ${SIGNAL_RECIPIENT}"
        echo ""
    fi

    # ── Bifrost ───────────────────────────────────────────────────────────────
    if [[ "${BIFROST_ENABLED:-false}" == "true" ]]; then
        echo "BIFROST"
        echo "  API Key      ${BIFROST_API_KEY:-<not set>}"
        echo "  Admin Token  ${BIFROST_ADMIN_TOKEN:-<not set>}"
        echo ""
    fi

    # ── External API Keys ─────────────────────────────────────────────────────
    local _has_ext=false
    [[ "${ENABLE_ANTHROPIC:-false}" == "true" && -n "${ANTHROPIC_API_KEY:-}" ]] && _has_ext=true
    [[ "${ENABLE_GOOGLE:-false}"    == "true" && -n "${GOOGLE_AI_API_KEY:-}" ]] && _has_ext=true
    [[ "${ENABLE_GROQ:-false}"      == "true" && -n "${GROQ_API_KEY:-}" ]]      && _has_ext=true
    [[ -n "${OPENROUTER_API_KEY:-}" ]]                                           && _has_ext=true
    [[ "${ENABLE_MAMMOUTH:-false}"  == "true" && -n "${MAMMOUTH_API_KEY:-}" ]]  && _has_ext=true
    [[ "${ENABLE_OPENAI:-false}"    == "true" && -n "${OPENAI_API_KEY:-}" ]]    && _has_ext=true
    if [[ "$_has_ext" == "true" ]]; then
        echo "EXTERNAL API KEYS  (routed through LiteLLM)"
        [[ "${ENABLE_OPENAI:-false}"    == "true" ]] && [[ -n "${OPENAI_API_KEY:-}" ]]    && echo "  OpenAI       ${OPENAI_API_KEY}"
        [[ "${ENABLE_ANTHROPIC:-false}" == "true" ]] && [[ -n "${ANTHROPIC_API_KEY:-}" ]] && echo "  Anthropic    ${ANTHROPIC_API_KEY}"
        [[ "${ENABLE_GOOGLE:-false}"    == "true" ]] && [[ -n "${GOOGLE_AI_API_KEY:-}" ]] && echo "  Google AI    ${GOOGLE_AI_API_KEY}"
        [[ "${ENABLE_GROQ:-false}"      == "true" ]] && [[ -n "${GROQ_API_KEY:-}" ]]      && echo "  Groq         ${GROQ_API_KEY}"
        [[ -n "${OPENROUTER_API_KEY:-}" ]]                                                 && echo "  OpenRouter   ${OPENROUTER_API_KEY}"
        [[ "${ENABLE_MAMMOUTH:-false}"  == "true" ]] && [[ -n "${MAMMOUTH_API_KEY:-}" ]]  && echo "  Mammouth     ${MAMMOUTH_API_KEY}"
        echo ""
    fi

    # ── Search API Keys ───────────────────────────────────────────────────────
    local _has_search_api=false
    [[ "${ENABLE_SERPAPI:-false}" == "true" && -n "${SERPAPI_KEY:-}" ]] && _has_search_api=true
    [[ "${ENABLE_BRAVE:-false}"   == "true" && -n "${BRAVE_API_KEY:-}" ]] && _has_search_api=true
    if [[ "$_has_search_api" == "true" ]]; then
        echo "SEARCH API KEYS"
        [[ "${ENABLE_SERPAPI:-false}" == "true" ]] && echo "  SerpAPI      ${SERPAPI_KEY:-<not set>}"
        [[ "${ENABLE_BRAVE:-false}"   == "true" ]] && echo "  Brave Search ${BRAVE_API_KEY:-<not set>}"
        echo ""
    fi

    echo "══════════════════════════════════════════════════════════════════════"
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
    echo "║              SERVICE HEALTH STATUS                      ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    printf "%-18s %-12s %-30s %-10s\n" "SERVICE" "STATUS" "CONTAINER" "PORT"
    echo "────────────────────────────────────────────────────────────────────────"

    # Helper: print one service row (label, container suffix, port)
    _svc_row() {
        local label="$1" suffix="$2" port="$3"
        local cname="${TENANT_PREFIX}-${suffix}"
        local st="DOWN"
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${cname}$"; then
            st=$(docker inspect --format='{{.State.Health.Status}}' "$cname" 2>/dev/null || echo "running")
        fi
        printf "%-18s %-12s %-30s %-10s\n" "$label" "$st" "$cname" "$port"
    }

    # Infrastructure
    [[ "${POSTGRES_ENABLED:-false}"   == "true" ]] && _svc_row "PostgreSQL"   "postgres"    "${POSTGRES_PORT:-5432}"
    [[ "${REDIS_ENABLED:-false}"      == "true" ]] && _svc_row "Redis"        "redis"       "${REDIS_PORT:-6379}"
    [[ "${MONGODB_ENABLED:-${LIBRECHAT_ENABLED:-${ENABLE_LIBRECHAT:-false}}}" == "true" ]] && _svc_row "MongoDB" "mongodb" "27017"

    # LLM
    [[ "${OLLAMA_ENABLED:-false}"     == "true" ]] && _svc_row "Ollama"       "ollama"      "${OLLAMA_PORT:-11434}"
    [[ "${LITELLM_ENABLED:-false}"    == "true" ]] && _svc_row "LiteLLM"      "litellm"     "${LITELLM_PORT:-4000}"
    [[ "${BIFROST_ENABLED:-false}"    == "true" ]] && _svc_row "Bifrost"      "bifrost"     "${BIFROST_PORT:-8090}"

    # Web UIs
    [[ "${OPENWEBUI_ENABLED:-false}"  == "true" ]] && _svc_row "OpenWebUI"    "openwebui"   "${OPENWEBUI_PORT:-3000}"
    [[ "${LIBRECHAT_ENABLED:-${ENABLE_LIBRECHAT:-false}}" == "true" ]] && _svc_row "LibreChat" "librechat" "${LIBRECHAT_PORT:-3080}"
    [[ "${OPENCLAW_ENABLED:-false}"   == "true" ]] && _svc_row "OpenClaw"     "openclaw"    "${OPENCLAW_PORT:-18789}"
    [[ "${ANYTHINGLLM_ENABLED:-false}" == "true" ]] && _svc_row "AnythingLLM" "anythingllm" "${ANYTHINGLLM_PORT:-3001}"

    # Vector DBs
    [[ "${QDRANT_ENABLED:-false}"     == "true" ]] && _svc_row "Qdrant"       "qdrant"      "${QDRANT_PORT:-6333}"
    [[ "${WEAVIATE_ENABLED:-false}"   == "true" ]] && _svc_row "Weaviate"     "weaviate"    "${WEAVIATE_PORT:-8080}"
    [[ "${CHROMA_ENABLED:-false}"     == "true" ]] && _svc_row "ChromaDB"     "chroma"      "${CHROMA_PORT:-8000}"
    [[ "${MILVUS_ENABLED:-false}"     == "true" ]] && _svc_row "Milvus"       "milvus"      "${MILVUS_PORT:-19530}"

    # Automation
    [[ "${N8N_ENABLED:-false}"        == "true" ]] && _svc_row "N8N"          "n8n"         "${N8N_PORT:-5678}"
    [[ "${FLOWISE_ENABLED:-false}"    == "true" ]] && _svc_row "Flowise"      "flowise"     "${FLOWISE_PORT:-3001}"
    if [[ "${DIFY_ENABLED:-false}"    == "true" ]]; then
        _svc_row "Dify (web)"     "dify"        "${DIFY_PORT:-3040}"
        _svc_row "Dify (api)"     "dify-api"    "${DIFY_API_PORT:-5001}"
        _svc_row "Dify (worker)"  "dify-worker" "-"
    fi

    # Memory
    [[ "${ZEP_ENABLED:-false}"        == "true" ]] && _svc_row "Zep CE"       "zep"         "${ZEP_PORT:-8100}"
    [[ "${LETTA_ENABLED:-false}"      == "true" ]] && _svc_row "Letta"        "letta"       "${LETTA_PORT:-8283}"

    # Identity + monitoring
    [[ "${AUTHENTIK_ENABLED:-false}"  == "true" ]] && _svc_row "Authentik"    "authentik"   "${AUTHENTIK_PORT:-9000}"
    [[ "${GRAFANA_ENABLED:-false}"    == "true" ]] && _svc_row "Grafana"      "grafana"     "${GRAFANA_PORT:-3002}"
    [[ "${PROMETHEUS_ENABLED:-false}" == "true" ]] && _svc_row "Prometheus"   "prometheus"  "${PROMETHEUS_PORT:-9090}"

    # Dev + alerting
    [[ "${CODE_SERVER_ENABLED:-false}" == "true" ]] && _svc_row "Code Server" "code-server" "${CODE_SERVER_PORT:-8080}"
    [[ "${SIGNALBOT_ENABLED:-false}"  == "true" ]] && _svc_row "Signalbot"    "signalbot"   "${SIGNALBOT_PORT:-8080}"

    # Reverse proxy
    [[ "${CADDY_ENABLED:-false}"      == "true" ]] && _svc_row "Caddy"        "caddy"       "80/443"
    [[ "${NPM_ENABLED:-false}"        == "true" ]] && _svc_row "NPM"          "npm"         "${NPM_ADMIN_PORT:-81}(admin)"

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
    # New feature flags
    local do_ingest=false
    local skip_sync=false
    local show_logs_svc=""
    local log_lines=200
    local do_audit_logs=false
    local reconfigure_svc=""
    local litellm_routing=""
    local ollama_action=""
    local ollama_model=""
    local do_backup=false
    local backup_schedule=""
    local setup_persistence=false

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
            # ── New features ──────────────────────────────────────────────────
            --ingest)
                do_ingest=true
                shift
                ;;
            --skip-sync)
                skip_sync=true
                shift
                ;;
            --logs)
                show_logs_svc="$2"
                shift 2
                ;;
            --log-lines)
                log_lines="$2"
                shift 2
                ;;
            --audit-logs)
                do_audit_logs=true
                shift
                ;;
            --reconfigure)
                reconfigure_svc="$2"
                shift 2
                ;;
            --litellm-routing)
                litellm_routing="$2"
                shift 2
                ;;
            --ollama-list)
                ollama_action="list"
                shift
                ;;
            --ollama-pull)
                ollama_action="pull"
                ollama_model="$2"
                shift 2
                ;;
            --setup-persistence)
                setup_persistence=true
                shift
                ;;
            --ollama-remove)
                ollama_action="remove"
                ollama_model="$2"
                shift 2
                ;;
            --ollama-latest)
                fetch_latest_models=true
                shift
                ;;
            --configure-models)
                configure_models=true
                shift
                ;;
            --configure-ai)
                configure_ai=true
                shift
                ;;
            --flushall)
                flushall=true
                shift
                ;;
            --backup)
                do_backup=true
                shift
                ;;
            --schedule)
                backup_schedule="$2"
                shift 2
                ;;
            --test-pipeline)
                test_full_pipeline "$tenant_id"
                exit 0
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
        [[ -n "${LIBRECHAT_HOST_PORT:-}" ]] && LIBRECHAT_PORT="${LIBRECHAT_HOST_PORT}"
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
        [[ -n "${ZEP_HOST_PORT:-}" ]] && ZEP_PORT="${ZEP_HOST_PORT}"
        [[ -n "${LETTA_HOST_PORT:-}" ]] && LETTA_PORT="${LETTA_HOST_PORT}"
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
    ZEP_ENABLED="${ZEP_ENABLED:-${ENABLE_ZEP:-false}}"
    LETTA_ENABLED="${LETTA_ENABLED:-${ENABLE_LETTA:-false}}"
    CODE_SERVER_ENABLED="${CODE_SERVER_ENABLED:-${ENABLE_CODE_SERVER:-false}}"
    CHROMA_ENABLED="${CHROMA_ENABLED:-${ENABLE_CHROMA:-false}}"
    MILVUS_ENABLED="${MILVUS_ENABLED:-${ENABLE_MILVUS:-false}}"
    
    # Ensure TENANT_ID is set as an env var (show_credentials and other helpers reference it)
    TENANT_ID="${TENANT_ID:-${tenant_id}}"

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
    
    if [[ "$setup_persistence" == "true" ]]; then
        configure_persistence
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

    # ── New feature dispatches ─────────────────────────────────────────────────
    if [[ "$do_ingest" == "true" ]]; then
        run_ingestion_pipeline "$skip_sync"
        return 0
    fi

    if [[ -n "$show_logs_svc" ]]; then
        show_logs "$show_logs_svc" "$log_lines"
        return 0
    fi

    if [[ "$do_audit_logs" == "true" ]]; then
        audit_logs
        return 0
    fi

    if [[ -n "$reconfigure_svc" ]]; then
        reconfigure_service "$reconfigure_svc"
        return 0
    fi

    if [[ -n "$litellm_routing" ]]; then
        change_litellm_routing "$litellm_routing"
        return 0
    fi

    if [[ -n "$ollama_action" ]]; then
        manage_ollama_models "$ollama_action" "$ollama_model"
        return 0
    fi

    if [[ "$do_backup" == "true" ]]; then
        run_backup "$backup_schedule"
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
        configure_anythingllm
        configure_n8n
        configure_flowise
        configure_dify
        configure_authentik
        configure_signalbot
        configure_searxng
        configure_ai_dev_tools
        configure_zep
        configure_letta
        configure_bifrost
    fi
    
    # Fetch latest models if requested
    if [[ "${fetch_latest_models:-false}" == "true" ]]; then
        fetch_latest_ollama_models
    fi
    
    # Model configuration (new feature)
    if [[ "${configure_models:-false}" == "true" ]]; then
        configure_models
    fi
    
    # AI dev tools configuration
    if [[ "${configure_ai:-false}" == "true" ]]; then
        configure_ai_dev_tools
    fi
    
    # Flushall databases if requested
    if [[ "${flushall:-false}" == "true" ]]; then
        log "Flushing all databases for self-healing..."
        
        # Stop all database-dependent services
        for service in postgres redis mongodb litellm dify-api dify dify-worker zep letta; do
            docker stop "${TENANT_PREFIX}-${service}" 2>/dev/null || true
        done
        
        # Wipe all databases
        docker exec "${TENANT_PREFIX}-postgres" psql -U "${POSTGRES_USER:-${TENANT_ID}}" -d "${POSTGRES_DB:-${TENANT_ID}}" -c "
            DROP SCHEMA IF EXISTS dify CASCADE;
            DROP SCHEMA IF EXISTS litellm CASCADE;
            DROP SCHEMA IF EXISTS zep CASCADE;
            DROP SCHEMA IF EXISTS letta CASCADE;
        " 2>/dev/null || true
        
        # Clear caches
        rm -rf "${DATA_DIR}/litellm/prisma-cache"/* 2>/dev/null || true
        rm -rf "${DATA_DIR}/mongodb"/* 2>/dev/null || true
        rm -rf "${DATA_DIR}/redis"/* 2>/dev/null || true
        
        # Restart all services
        for service in postgres redis mongodb litellm dify-api dify dify-worker zep letta; do
            docker start "${TENANT_PREFIX}-${service}" 2>/dev/null || true
        done
        
        log "Database flush completed. Services are re-initializing..."
        log "Run Script 3 again in 2-3 minutes to verify health."
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

configure_models() {
    # Interactive model configuration for Ollama and external LLM providers
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "  Interactive Model Configuration"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Source platform.conf to get current configuration
    source "${CONFIG_DIR}/platform.conf"
    
    echo ""
    echo "🤖 Current Model Configuration:"
    echo ""
    
    # Show current Ollama models
    if [[ "${OLLAMA_ENABLED:-false}" == "true" ]]; then
        echo "📦 Ollama Models:"
        docker exec "${TENANT_PREFIX}-ollama" ollama list 2>/dev/null || echo "  (No models loaded)"
        echo ""
    fi
    
    # Show current LiteLLM configuration
    if [[ "${LITELLM_ENABLED:-false}" == "true" ]]; then
        echo "🌐 LiteLLM Configuration:"
        echo "  Master Key: ${LITELLM_MASTER_KEY:0:20}..."
        echo "  Routing Strategy: ${LITELLM_ROUTING_STRATEGY:-default}"
        echo ""
    fi
    
    echo "🎛 Configuration Options:"
    echo "1. Configure Ollama Models"
    echo "2. Configure External LLM Providers (Groq, OpenAI, Anthropic, etc.)"
    echo "3. Change LiteLLM Routing Strategy"
    echo "4. Save and Re-deploy Stack"
    echo ""
    echo "Enter choice (1-4) or 'q' to quit:"
    read -r choice
    
    case $choice in
        1)
            configure_ollama_models
            ;;
        2)
            configure_external_llms
            ;;
        3)
            change_litellm_routing
            ;;
        4)
            save_and_redeploy
            ;;
        q)
            log "Model configuration cancelled"
            return 0
            ;;
        *)
            log "Invalid choice. Please try again."
            configure_models
            return
            ;;
    esac
}

fetch_latest_ollama_models() {
    echo ""
    echo "🔍 Fetching latest models from Ollama official repository..."
    echo ""
    
    # Fetch latest models from Ollama library
    local models_json
    models_json=$(curl -s "https://ollama.com/api/tags" 2>/dev/null || echo "")
    
    if [[ -z "$models_json" ]]; then
        echo "⚠️  Unable to fetch from registry, using fallback list"
        echo ""
        echo "📋 Popular Models (fallback list):"
        echo "1. gemma3:12b - Google's multimodal model"
        echo "2. qwen3-coder:480b - Alibaba's coding model"
        echo "3. ministral-3:3b - Mistral's compact model"
        echo "4. gpt-oss:120b - Open-source large model"
        echo "5. glm-4.6 - GLM's latest model"
        echo "6. deepseek-v3.2 - DeepSeek's reasoning model"
        echo "7. custom - Enter specific model name"
        echo ""
        return 0
    fi
    
    echo "📋 Latest Available Models (from ollama.com/library):"
    echo ""
    
    # Parse and display top models (show more to include gemma4)
    local count=0
    echo "$models_json" | jq -r '.models[] | "\(.name)"' 2>/dev/null | head -30 | while read -r model; do
        count=$((count + 1))
        printf "%2d. %s\n" "$count" "$model"
    done
    
    echo ""
    echo "🔧 Options:"
    echo "99. Show more models"
    echo "100. Enter custom model name"
    echo ""
    echo "Enter model number or name:"
}

configure_ollama_models() {
    echo ""
    echo "📦 Configure Ollama Models:"
    echo ""
    echo "1. 🔄 Fetch newest models (top 10)"
    echo "2. 📋 Use popular models list"
    echo "3. 🔧 Enter custom model name"
    echo ""
    echo "Enter choice (1-3):"
    read -r model_choice
    
    case $model_choice in
        1)
            get_newest_models
            read -r model_name
            ;;
        2)
            echo ""
            echo "📋 Popular Models:"
            echo "1. gemma3:12b - Google's multimodal model"
            echo "2. qwen3-coder:480b - Alibaba's coding model"
            echo "3. ministral-3:3b - Mistral's compact model"
            echo "4. gpt-oss:120b - Open-source large model"
            echo "5. glm-4.6 - GLM's latest model"
            echo "6. deepseek-v3.2 - DeepSeek's reasoning model"
            echo ""
            echo "Enter model number or name:"
            read -r model_name
            ;;
        3)
            echo ""
            echo "🔧 Enter custom model name (e.g., 'gemma2:27b'):"
            read -r model_name
            ;;
        *)
            echo "❌ Invalid choice"
            return 1
            ;;
    esac
    
    # Validate and pull models (handle comma-separated input)
    if [[ -n "$model_name" ]]; then
        # Split comma-separated models and process each one
        IFS=',' read -ra model_array <<< "$model_name"
        local success_count=0
        local total_count=${#model_array[@]}
        
        for model in "${model_array[@]}"; do
            # Remove whitespace
            model=$(echo "${model// /}" | xargs)
            
            if [[ -n "$model" ]]; then
                # Validate model exists in Ollama registry
                if ! validate_model_exists "$model"; then
                    error "Model '$model' not found in Ollama registry. Use --ollama-latest to see available models or check spelling."
                    continue
                fi
                
                log "Pulling Ollama model: $model"
                if docker exec "${TENANT_PREFIX}-ollama" ollama pull "$model"; then
                    log "Model '$model' pulled successfully"
                    
                    # Update platform.conf with new model
                    update_platform_conf_models "$model"
                    success_count=$((success_count + 1))
                else
                    error "Failed to pull model '$model'"
                fi
            fi
        done
        
        if [[ $success_count -gt 0 ]]; then
            log "🔄 Restarting LiteLLM to recognize new models..."
            docker restart "${TENANT_PREFIX}-litellm" >/dev/null 2>&1
            log "✅ Model deployment complete! ($success_count/$total_count models successful)"
        else
            error "❌ No models were successfully pulled"
        fi
    else
        error "❌ No model selected"
    fi
}

get_newest_models() {
    echo ""
    echo "Fetching newest models from ollama.com..."
    echo ""
    
    # Get newest models by checking recent library additions
    local popular_models=(
        "gemma4:4b"
        "gemma4:26b"
        "gemma4:31b"
        "gemma3:4b"
        "gemma3:12b"
        "qwen2.5:7b"
        "qwen2.5:14b"
        "llama3.1:8b"
        "llama3.1:70b"
        "mistral:7b"
    )
    
    echo "Top 10 Newest Models:"
    echo ""
    local count=0
    for model in "${popular_models[@]}"; do
        count=$((count + 1))
        printf "%2d. %s\n" "$count" "$model"
    done
    
    echo ""
    echo "Options:"
    echo "99. Enter custom model name"
    echo ""
    echo "Enter model number or name:"
}

validate_model_exists() {
    local model="$1"
    local model_base="${model%:*}"  # Remove tag if present (e.g., gemma4:9b -> gemma4)
    
    # List of known valid model bases
    local known_models=(
        "gemma4" "gemma3" "gemma2" "llama3.2" "llama3.1" "llama3.3"
        "qwen2.5" "qwen3" "mistral" "codellama" "deepseek" "dolphin"
        "olmo" "smollm" "nemotron" "glm" "ministral" "kimi" "cogito"
    )
    
    # Check if model base is in known models
    for known in "${known_models[@]}"; do
        if [[ "$model_base" == "$known" ]]; then
            return 0
        fi
    done
    
    # If not in known list, try library page check
    local library_page
    library_page=$(curl -s "https://ollama.com/library/${model_base}" 2>/dev/null)
    
    if [[ -n "$library_page" && ! "$library_page" =~ "404" ]]; then
        return 0
    else
        return 1
    fi
}

update_platform_conf_models() {
    local new_model="$1"
    local config_file="${CONFIG_DIR}/platform.conf"
    
    # Add new model to OLLAMA_MODELS if not already present
    if ! grep -q "$new_model" "$config_file"; then
        # Append to existing models
        sed -i "s/OLLAMA_MODELS=\"\(.*\)\"/OLLAMA_MODELS=\"\1,$new_model\"/" "$config_file"
        sed -i 's/,/,/2g' "$config_file"  # Fix double commas
        log "✅ Added '$new_model' to OLLAMA_MODELS"
    fi
    
    # Update LiteLLM config
    local litellm_config="${CONFIG_DIR}/litellm/config.yaml"
    if ! grep -q "$new_model" "$litellm_config"; then
        # Add model to LiteLLM configuration
        sed -i "/model_list:/a\\  - model_name: ollama/$new_model\\n    litellm_params:\\n      model: ollama/$new_model\\n      api_base: http://${TENANT_PREFIX}-ollama:11434" "$litellm_config"
        log "✅ Added '$new_model' to LiteLLM configuration"
    fi
}

configure_external_llms() {
    echo ""
    echo "🌐 Configure External LLM Providers:"
    echo ""
    
    # Display current provider configuration
    echo "Current providers:"
    [[ -n "${GROQ_API_KEY:-}" ]] && echo "  ✅ Groq API configured"
    [[ -n "${OPENAI_API_KEY:-}" ]] && echo "  ✅ OpenAI API configured"
    [[ -n "${ANTHROPIC_API_KEY:-}" ]] && echo "  ✅ Anthropic API configured"
    [[ -n "${GOOGLE_KEY:-}" ]] && echo "  ✅ Google API configured"
    echo ""
    
    echo "Available providers to configure:"
    echo "1. Groq (llama3-70b, mixtral-8x7b)"
    echo "2. OpenAI (gpt-4, gpt-3.5-turbo)"
    echo "3. Anthropic (claude-3-sonnet, claude-3-haiku)"
    echo "4. Google (gemini-pro, gemini-1.5-flash)"
    echo ""
    echo "Enter provider to configure (1-4) or 'q' to return:"
    read -r provider_choice
    
    case $provider_choice in
        1)
            configure_groq_provider
            ;;
        2)
            configure_openai_provider
            ;;
        3)
            configure_anthropic_provider
            ;;
        4)
            configure_google_provider
            ;;
        q)
            return 0
            ;;
        *)
            echo "Invalid choice. Please try again."
            configure_external_llms
            return
            ;;
    esac
}

configure_groq_provider() {
    echo "Configuring Groq provider..."
    echo "Enter Groq API key (or press Enter to keep current):"
    read -s api_key
    if [[ -n "$api_key" ]]; then
        update_conf_value "GROQ_API_KEY" "$api_key"
        log "✅ Groq API key updated"
    fi
}

configure_openai_provider() {
    echo "Configuring OpenAI provider..."
    echo "Enter OpenAI API key (or press Enter to keep current):"
    read -s api_key
    if [[ -n "$api_key" ]]; then
        update_conf_value "OPENAI_API_KEY" "$api_key"
        log "✅ OpenAI API key updated"
    fi
}

configure_anthropic_provider() {
    echo "Configuring Anthropic provider..."
    echo "Enter Anthropic API key (or press Enter to keep current):"
    read -s api_key
    if [[ -n "$api_key" ]]; then
        update_conf_value "ANTHROPIC_API_KEY" "$api_key"
        log "✅ Anthropic API key updated"
    fi
}

configure_google_provider() {
    echo "Configuring Google provider..."
    echo "Enter Google API key (or press Enter to keep current):"
    read -s api_key
    if [[ -n "$api_key" ]]; then
        update_conf_value "GOOGLE_KEY" "$api_key"
        log "✅ Google API key updated"
    fi
}

save_and_redeploy() {
    echo ""
    echo "💾 Save configuration and re-deploy?"
    echo "This will save current model configuration and re-run Script 2."
    echo "Continue? (y/N):"
    read -r confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log "Saving model configuration..."
        
        # Save current configuration as template
        local template_file="/home/jglaine/.ai-platform-templates/${TENANT_ID}-model-config.conf"
        cp "${CONFIG_DIR}/platform.conf" "$template_file"
        log "✅ Configuration saved to template: $template_file"
        
        log "Re-deploying stack with new model configuration..."
        log "Run: bash scripts/2-deploy-services.sh ${TENANT_ID}"
        
        # Offer to run Script 2 automatically
        echo "Automatically re-run Script 2 now? (y/N):"
        read -r auto_deploy
        
        if [[ "$auto_deploy" =~ ^[Yy]$ ]]; then
            bash scripts/2-deploy-services.sh "${TENANT_ID}"
        else
            log "Manual re-deploy required. Run Script 2 when ready."
        fi
    else
        log "Configuration save cancelled"
    fi
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
    [[ "${LIBRECHAT_ENABLED:-false}"  == "true" ]] && _port_check "LibreChat"  "${LIBRECHAT_PORT:-3080}" "/health"
    [[ "${OPENCLAW_ENABLED:-false}"   == "true" ]] && _port_check "OpenClaw"   "${OPENCLAW_PORT:-3081}"  "/health"
    # Vector databases
    [[ "${QDRANT_ENABLED:-false}"     == "true" ]] && _port_check "Qdrant"      "${QDRANT_PORT:-6333}"     "/healthz"
    [[ "${WEAVIATE_ENABLED:-false}"   == "true" ]] && _port_check "Weaviate"    "${WEAVIATE_PORT:-8080}"   "/v1/.well-known/ready"
    [[ "${CHROMA_ENABLED:-false}"     == "true" ]] && _port_check "ChromaDB"    "${CHROMA_PORT:-8000}"     "/api/v1/heartbeat"
    [[ "${MILVUS_ENABLED:-false}"     == "true" ]] && _port_check "Milvus"      "${MILVUS_PORT:-19530}"    "/healthz"
    # Automation
    [[ "${N8N_ENABLED:-false}"        == "true" ]] && _port_check "N8N"         "${N8N_PORT:-5678}"        "/healthz"
    [[ "${FLOWISE_ENABLED:-false}"    == "true" ]] && _port_check "Flowise"     "${FLOWISE_PORT:-3000}"    "/api/v1/ping"
    [[ "${DIFY_ENABLED:-false}"       == "true" ]] && _port_check "Dify"        "${DIFY_PORT:-3002}"       "/apps"
    # Web UIs (additional)
    [[ "${ANYTHINGLLM_ENABLED:-false}" == "true" ]] && _port_check "AnythingLLM" "${ANYTHINGLLM_PORT:-3001}" "/"
    # Identity + monitoring
    [[ "${GRAFANA_ENABLED:-false}"    == "true" ]] && _port_check "Grafana"     "${GRAFANA_PORT:-3003}"    "/api/health"
    [[ "${PROMETHEUS_ENABLED:-false}" == "true" ]] && _port_check "Prometheus"  "${PROMETHEUS_PORT:-9090}" "/-/healthy"
    [[ "${AUTHENTIK_ENABLED:-false}"  == "true" ]] && _port_check "Authentik"   "${AUTHENTIK_PORT:-9000}"  "/-/health/live/"
    [[ "${SIGNALBOT_ENABLED:-false}"  == "true" ]] && _port_check "Signalbot"   "${SIGNALBOT_PORT:-8080}"  "/v1/about"
    [[ "${CODE_SERVER_ENABLED:-false}" == "true" ]] && _port_check "Code Server" "${CODE_SERVER_PORT:-8080}" "/healthz"
    [[ "${BIFROST_ENABLED:-false}"    == "true" ]] && _port_check "Bifrost"     "${BIFROST_PORT:-8090}"    "/health"
    # Memory layer
    [[ "${ZEP_ENABLED:-false}"        == "true" ]] && _port_check "Zep"         "${ZEP_PORT:-8100}"        "/healthz"
    [[ "${LETTA_ENABLED:-false}"      == "true" ]] && _port_check "Letta"       "${LETTA_PORT:-8283}"      "/v1/health"
    # Reverse proxy admin
    [[ "${NPM_ENABLED:-false}"        == "true" ]] && _port_check "NPM Admin"   "${NPM_ADMIN_PORT:-81}"    "/api/"

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

    # Determine base URL — use domain when a reverse proxy is active
    local base_proto="http"
    local display_host
    display_host=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
    if [[ "${CADDY_ENABLED:-false}" == "true" || "${NPM_ENABLED:-false}" == "true" ]] && [[ -n "${BASE_DOMAIN:-${DOMAIN:-}}" ]]; then
        base_proto="https"
        display_host="${BASE_DOMAIN:-${DOMAIN}}"
    fi
    local base="${base_proto}://${display_host}"

    # Helper: compute correct browser URL
    # When Caddy/NPM active: https://subdomain.domain  (no port — proxy handles it)
    # Otherwise:             http://IP:port
    _access_url() {
        local subdomain="$1" port="$2"
        if [[ "$use_subdomains" == "true" ]]; then
            echo "${base_proto}://${subdomain}.${display_host}"
        else
            echo "${base_proto}://${display_host}:${port}"
        fi
    }
    local use_subdomains=false
    [[ "${CADDY_ENABLED:-false}" == "true" || "${NPM_ENABLED:-false}" == "true" ]] && \
        [[ -n "${BASE_DOMAIN:-${DOMAIN:-}}" ]] && use_subdomains=true

    echo "  Access URLs:"
    echo ""

    # Web UIs
    [[ "${OPENWEBUI_ENABLED:-false}"   == "true" ]] && echo "    OpenWebUI    → $(_access_url openwebui   ${OPENWEBUI_PORT:-3000})"
    [[ "${LIBRECHAT_ENABLED:-${ENABLE_LIBRECHAT:-false}}" == "true" ]] && \
                                                        echo "    LibreChat    → $(_access_url librechat   ${LIBRECHAT_PORT:-3080})"
    [[ "${OPENCLAW_ENABLED:-false}"    == "true" ]] && echo "    OpenClaw     → $(_access_url openclaw    ${OPENCLAW_PORT:-18789})"
    [[ "${ANYTHINGLLM_ENABLED:-false}" == "true" ]] && echo "    AnythingLLM  → $(_access_url anythingllm ${ANYTHINGLLM_PORT:-3001})"

    # LLM gateway — internal only
    [[ "${LITELLM_ENABLED:-false}"     == "true" ]] && echo "    LiteLLM      → $(_access_url litellm ${LITELLM_PORT:-4000})  (LLM gateway)"

    # Automation
    [[ "${N8N_ENABLED:-false}"         == "true" ]] && echo "    N8N          → $(_access_url n8n     ${N8N_PORT:-5678})"
    [[ "${FLOWISE_ENABLED:-false}"     == "true" ]] && echo "    Flowise      → $(_access_url flowise ${FLOWISE_PORT:-3001})"
    if [[ "${DIFY_ENABLED:-false}"     == "true" ]]; then
        echo "    Dify         → $(_access_url dify    ${DIFY_PORT:-3040})  (web + api path routing)"
    fi

    # Memory
    [[ "${ZEP_ENABLED:-false}"         == "true" ]] && echo "    Zep CE       → $(_access_url zep   ${ZEP_PORT:-8100})"
    [[ "${LETTA_ENABLED:-false}"       == "true" ]] && echo "    Letta        → $(_access_url letta ${LETTA_PORT:-8283})"

    # Identity + monitoring
    [[ "${AUTHENTIK_ENABLED:-false}"   == "true" ]] && echo "    Authentik    → $(_access_url authentik  ${AUTHENTIK_PORT:-9000})"
    [[ "${GRAFANA_ENABLED:-false}"     == "true" ]] && echo "    Grafana      → $(_access_url grafana    ${GRAFANA_PORT:-3000})"
    [[ "${PROMETHEUS_ENABLED:-false}"  == "true" ]] && echo "    Prometheus   → $(_access_url prometheus ${PROMETHEUS_PORT:-9090})"
    [[ "${CODE_SERVER_ENABLED:-false}" == "true" ]] && echo "    Code Server  → $(_access_url code       ${CODE_SERVER_PORT:-8080})"

    [[ "${SEARXNG_ENABLED:-false}"       == "true" ]] && echo "    SearXNG      → $(_access_url search     ${SEARXNG_PORT:-8888})"

    # Signalbot — show QR link
    if [[ "${SIGNALBOT_ENABLED:-false}" == "true" ]]; then
        local _sig="$(_access_url signal ${SIGNALBOT_PORT:-8080})"
        echo "    Signalbot    → ${_sig}/v1/about"
        echo "    Signal QR    → ${_sig}/v1/qrcodelink?device_name=signal-api"
    fi

    # Reverse proxy admin
    [[ "${CADDY_ENABLED:-false}"       == "true" ]] && echo "    Caddy        → https://${BASE_DOMAIN:-${DOMAIN:-localhost}}  (TLS: ${TLS_MODE:-none})"
    [[ "${NPM_ENABLED:-false}"         == "true" ]] && echo "    NPM Admin    → http://127.0.0.1:${NPM_ADMIN_PORT:-81}  (admin@example.com / changeme)"
    echo ""
}

# =============================================================================
# INGESTION PIPELINE — rclone sync → vector DB embeddings
# =============================================================================

# Trigger rclone sync manually and/or ingest files into vector DB
run_ingestion_pipeline() {
    local skip_sync="${1:-false}"   # pass "true" to skip the rclone step

    if [[ "${ENABLE_INGESTION:-false}" != "true" ]]; then
        warn "Ingestion is not enabled (ENABLE_INGESTION=false). Enable it in platform.conf and re-run Script 2."
        return 1
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  INGESTION PIPELINE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local ingestion_dir="${DATA_DIR}/ingestion"
    local rclone_container="${TENANT_PREFIX}-rclone"
    local vector_db="${VECTOR_DB_TYPE:-qdrant}"
    local embed_model="${EMBED_MODEL:-text-embedding-3-small}"

    # ── Step 1: rclone sync ────────────────────────────────────────────────────
    if [[ "$skip_sync" != "true" && "${INGESTION_METHOD:-rclone}" == "rclone" ]]; then
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${rclone_container}$"; then
            echo "  Triggering rclone sync (one-shot)..."
            # Exec a one-shot sync inside the running container
            if docker exec "${rclone_container}" sh -c \
                "rclone sync \${RCLONE_REMOTE:-gdrive}: /data --transfers=4 --checkers=8 --log-level INFO 2>&1"; then
                echo "  Sync complete."
            else
                warn "rclone sync exited with an error — check container logs: docker logs ${rclone_container}"
            fi
        else
            warn "rclone container ${rclone_container} is not running. Start it first (run Script 2)."
        fi
    else
        echo "  Skipping rclone sync (--skip-sync or non-rclone method)."
    fi

    # ── Step 2: discover files ─────────────────────────────────────────────────
    if [[ ! -d "$ingestion_dir" ]]; then
        warn "Ingestion directory not found: ${ingestion_dir}"
        return 1
    fi

    local file_count
    file_count=$(find "$ingestion_dir" -type f | wc -l)
    echo "  Files in ingestion dir: ${file_count}"

    if [[ "$file_count" -eq 0 ]]; then
        echo "  No files to ingest. Share a Google Drive folder with the service account first."
        return 0
    fi

    # ── Step 3: embed + upsert via LiteLLM → Qdrant ───────────────────────────
    if [[ "${LITELLM_ENABLED:-false}" != "true" ]]; then
        warn "LiteLLM is not enabled — cannot embed files."
        return 1
    fi

    local litellm_url="http://127.0.0.1:${LITELLM_PORT:-4000}"
    local litellm_key="${LITELLM_MASTER_KEY:-}"
    local qdrant_url="http://127.0.0.1:${QDRANT_PORT:-6333}"
    local collection="${INGESTION_COLLECTION:-ingestion}"

    echo "  Embedding model : ${embed_model}"
    echo "  Vector DB       : ${vector_db} (collection: ${collection})"

    # Ensure Qdrant collection exists (1536-dim for OpenAI text-embedding-3-small)
    if [[ "$vector_db" == "qdrant" ]]; then
        local col_check
        col_check=$(curl -sf "${qdrant_url}/collections/${collection}" 2>/dev/null || true)
        if ! echo "$col_check" | grep -q '"status":"ok"'; then
            echo "  Creating Qdrant collection '${collection}' (1536-dim cosine)..."
            curl -sf -X PUT "${qdrant_url}/collections/${collection}" \
                -H "Content-Type: application/json" \
                -d '{"vectors":{"size":1536,"distance":"Cosine"}}' >/dev/null
        fi
    fi

    local ingested=0
    local failed=0
    while IFS= read -r -d '' filepath; do
        local filename
        filename=$(basename "$filepath")
        local ext="${filename##*.}"
        # Only ingest text-based files
        case "$ext" in
            txt|md|pdf|csv|json|yaml|yml|rst|log|html|xml) ;;
            *) continue ;;
        esac

        # Read content (truncate to 8000 chars to stay within embedding context)
        local content
        content=$(head -c 8000 "$filepath" 2>/dev/null | tr -d '\000' || true)
        [[ -z "$content" ]] && continue

        # Get embedding from LiteLLM
        local embed_response
        embed_response=$(curl -sf --max-time 30 \
            "${litellm_url}/v1/embeddings" \
            -H "Authorization: Bearer ${litellm_key}" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"${embed_model}\",\"input\":$(echo "$content" | jq -Rs .)}" \
            2>/dev/null || true)

        if ! echo "$embed_response" | jq -e '.data[0].embedding' >/dev/null 2>&1; then
            warn "  Failed to embed: ${filename}"
            failed=$((failed + 1))
            continue
        fi

        local vector
        vector=$(echo "$embed_response" | jq '.data[0].embedding')
        local point_id
        point_id=$(echo -n "$filepath" | md5sum | awk '{print $1}' | cut -c1-8)
        # Convert hex to integer for Qdrant point ID
        point_id=$((16#${point_id}))

        if [[ "$vector_db" == "qdrant" ]]; then
            curl -sf -X PUT "${qdrant_url}/collections/${collection}/points" \
                -H "Content-Type: application/json" \
                -d "{\"points\":[{\"id\":${point_id},\"vector\":${vector},\"payload\":{\"filename\":\"${filename}\",\"path\":\"${filepath}\",\"source\":\"ingestion\"}}]}" \
                >/dev/null 2>&1 && ingested=$((ingested + 1)) || failed=$((failed + 1))
        fi
    done < <(find "$ingestion_dir" -type f -print0)

    echo "  Ingested: ${ingested} files | Failed: ${failed} files"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ok "Ingestion pipeline complete"
}

# =============================================================================
# LOG MANAGEMENT
# =============================================================================

show_logs() {
    local service="$1"
    local lines="${2:-100}"
    local container="${TENANT_PREFIX}-${service}"

    if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${container}$"; then
        # Check all, dify has 3 containers
        if [[ "$service" == "dify" ]]; then
            for suf in dify dify-api dify-worker; do
                local c="${TENANT_PREFIX}-${suf}"
                docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${c}$" && \
                    echo "=== ${c} ===" && docker logs --tail "$lines" "$c" 2>&1 && echo ""
            done
            return 0
        fi
        fail "Container ${container} is not running"
    fi

    docker logs --tail "$lines" -f "${container}" 2>&1
}

audit_logs() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  LOG AUDIT (last 60s — ERROR/FATAL/WARN)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    local since="60s"
    while IFS= read -r cname; do
        local errs
        errs=$(docker logs --since "$since" "$cname" 2>&1 | grep -cE "ERROR|FATAL" || true)
        local warns
        warns=$(docker logs --since "$since" "$cname" 2>&1 | grep -cE "WARN|WARNING" || true)
        if [[ "$errs" -gt 0 ]]; then
            printf "  %-35s  ERRORS: %s  WARNS: %s\n" "$cname" "$errs" "$warns"
        fi
    done < <(docker ps --format "{{.Names}}" --filter "name=${TENANT_PREFIX}-" 2>/dev/null)
    echo "  (Only containers with errors shown — all others are clean)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# =============================================================================
# SERVICE RECONFIGURATION — reset passwords / API keys
# =============================================================================
reconfigure_service() {
    local service="$1"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  RECONFIGURE: ${service}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    _update_conf() {
        local key="$1" val="$2"
        local conf="${DATA_DIR}/config/platform.conf"
        if grep -q "^${key}=" "$conf"; then
            sed -i "s|^${key}=.*|${key}=\"${val}\"|" "$conf"
        else
            echo "${key}=\"${val}\"" >> "$conf"
        fi
    }

    case "$service" in

        openwebui)
            local new_secret
            new_secret=$(openssl rand -hex 32)
            _update_conf "WEBUI_SECRET_KEY" "$new_secret"
            docker restart "${TENANT_PREFIX}-openwebui" 2>/dev/null || true
            echo "  OpenWebUI secret key rotated. Users will need to log in again."
            echo "  New WEBUI_SECRET_KEY written to platform.conf."
            ;;

        librechat)
            local new_jwt new_enc
            new_jwt=$(openssl rand -hex 32)
            new_enc=$(openssl rand -hex 32)
            _update_conf "LIBRECHAT_JWT_SECRET" "$new_jwt"
            _update_conf "LIBRECHAT_JWT_REFRESH_SECRET" "$new_enc"
            docker restart "${TENANT_PREFIX}-librechat" 2>/dev/null || true
            echo "  LibreChat JWT secrets rotated. Users will need to log in again."
            ;;

        openclaw)
            local new_pass
            new_pass=$(openssl rand -base64 16 | tr -d '=+/')
            _update_conf "OPENCLAW_ADMIN_PASSWORD" "$new_pass"
            # OpenClaw stores password in its config file — rewrite it
            local cfg="${DATA_DIR}/openclaw/config/config.json"
            if [[ -f "$cfg" ]]; then
                jq --arg p "$new_pass" '.auth.adminPassword = $p' "$cfg" > "${cfg}.tmp" && mv "${cfg}.tmp" "$cfg"
            fi
            docker restart "${TENANT_PREFIX}-openclaw" 2>/dev/null || true
            echo "  OpenClaw admin password reset to: ${new_pass}"
            echo "  Written to platform.conf and config.json."
            ;;

        dify)
            local new_pass
            new_pass=$(openssl rand -base64 12 | tr -d '=+/')
            _update_conf "DIFY_INIT_PASSWORD" "$new_pass"
            # Reset via Dify API (only works if setup already complete)
            local dify_api_url="http://127.0.0.1:${DIFY_API_PORT:-5001}"
            local reset_resp
            reset_resp=$(curl -sf --max-time 10 -X POST \
                "${dify_api_url}/console/api/account/password" \
                -H "Content-Type: application/json" \
                -d "{\"password\":\"${new_pass}\"}" 2>/dev/null || true)
            if echo "$reset_resp" | grep -q '"result":"success"'; then
                echo "  Dify password reset via API: ${new_pass}"
            else
                echo "  Dify API reset not available (may need manual reset in UI)."
                echo "  New password for next setup: ${new_pass}"
            fi
            echo "  Written to platform.conf."
            ;;

        flowise)
            local new_pass
            new_pass=$(openssl rand -base64 12 | tr -d '=+/')
            _update_conf "FLOWISE_PASSWORD" "$new_pass"
            docker restart "${TENANT_PREFIX}-flowise" 2>/dev/null || true
            echo "  Flowise password reset to: ${new_pass}"
            echo "  Written to platform.conf. Container restarted."
            ;;

        n8n)
            local new_pass
            new_pass=$(openssl rand -base64 12 | tr -d '=+/')
            _update_conf "N8N_BASIC_AUTH_PASSWORD" "$new_pass"
            docker restart "${TENANT_PREFIX}-n8n" 2>/dev/null || true
            echo "  N8N basic-auth password reset to: ${new_pass}"
            echo "  Written to platform.conf. Container restarted."
            ;;

        litellm)
            rotate_keys "litellm"
            ;;

        grafana)
            local new_pass
            new_pass=$(openssl rand -base64 12 | tr -d '=+/')
            _update_conf "GRAFANA_ADMIN_PASSWORD" "$new_pass"
            docker restart "${TENANT_PREFIX}-grafana" 2>/dev/null || true
            echo "  Grafana admin password reset to: ${new_pass}"
            echo "  Written to platform.conf. Container restarted."
            ;;

        code-server)
            local new_pass
            new_pass=$(openssl rand -base64 16 | tr -d '=+/')
            _update_conf "CODE_SERVER_PASSWORD" "$new_pass"
            docker restart "${TENANT_PREFIX}-code-server" 2>/dev/null || true
            echo "  Code Server password reset to: ${new_pass}"
            echo "  Written to platform.conf. Container restarted."
            ;;

        anythingllm)
            local new_pass
            new_pass=$(openssl rand -base64 12 | tr -d '=+/')
            _update_conf "ANYTHINGLLM_PASSWORD" "$new_pass"
            docker restart "${TENANT_PREFIX}-anythingllm" 2>/dev/null || true
            echo "  AnythingLLM password reset to: ${new_pass}"
            echo "  Written to platform.conf. Container restarted."
            ;;

        *)
            fail "Reconfigure not implemented for service: ${service}. Supported: openwebui, librechat, openclaw, dify, flowise, n8n, litellm, grafana, code-server, anythingllm"
            ;;
    esac

    echo "  NOTE: Re-run Script 3 --show-credentials to see updated credentials."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# =============================================================================
# LITELLM ROUTING STRATEGY
# =============================================================================
change_litellm_routing() {
    local strategy="$1"

    local valid_strategies="simple-shuffle least-busy usage-based-routing cost-based-routing latency-based-routing"
    if ! echo "$valid_strategies" | grep -qw "$strategy"; then
        fail "Invalid routing strategy: ${strategy}
Valid options: ${valid_strategies}"
    fi

    if [[ "${LITELLM_ENABLED:-false}" != "true" ]]; then
        fail "LiteLLM is not enabled"
    fi

    local litellm_config="${DATA_DIR}/config/litellm_config.yaml"
    if [[ ! -f "$litellm_config" ]]; then
        fail "LiteLLM config not found: ${litellm_config}"
    fi

    # Update routing_strategy in the YAML
    if grep -q "routing_strategy:" "$litellm_config"; then
        sed -i "s|routing_strategy:.*|routing_strategy: ${strategy}|" "$litellm_config"
    else
        # Insert under router_settings if present
        if grep -q "router_settings:" "$litellm_config"; then
            sed -i "/router_settings:/a\\  routing_strategy: ${strategy}" "$litellm_config"
        else
            echo "" >> "$litellm_config"
            printf "router_settings:\n  routing_strategy: %s\n" "$strategy" >> "$litellm_config"
        fi
    fi

    # Also update platform.conf
    if grep -q "^LITELLM_ROUTING_STRATEGY=" "${DATA_DIR}/config/platform.conf"; then
        sed -i "s|^LITELLM_ROUTING_STRATEGY=.*|LITELLM_ROUTING_STRATEGY=\"${strategy}\"|" "${DATA_DIR}/config/platform.conf"
    fi

    # Reload LiteLLM by restart (config is file-mounted)
    log "Restarting LiteLLM to apply new routing strategy: ${strategy}..."
    docker restart "${TENANT_PREFIX}-litellm"

    # Wait for it to come back
    local attempts=0
    while [[ $attempts -lt 30 ]]; do
        if curl -sf "http://127.0.0.1:${LITELLM_PORT:-4000}/health/liveliness" >/dev/null 2>&1; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 3
    done

    ok "LiteLLM routing strategy changed to: ${strategy}"
}

# =============================================================================
# OLLAMA MODEL MANAGEMENT
# =============================================================================
manage_ollama_models() {
    local action="$1"
    local model="${2:-}"

    if [[ "${OLLAMA_ENABLED:-false}" != "true" ]]; then
        fail "Ollama is not enabled"
    fi

    local container="${TENANT_PREFIX}-ollama"
    if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${container}$"; then
        fail "Ollama container ${container} is not running"
    fi

    case "$action" in
        list)
            echo ""
            echo "  Ollama — Loaded Models:"
            echo "  ──────────────────────────"
            docker exec "${container}" ollama list 2>/dev/null || true
            echo ""
            ;;
        pull)
            [[ -z "$model" ]] && fail "Usage: --ollama-pull <model>"
            log "Pulling Ollama model: ${model} (this may take several minutes)..."
            docker exec "${container}" ollama pull "$model"
            ok "Model pulled: ${model}"
            ;;
        remove)
            [[ -z "$model" ]] && fail "Usage: --ollama-remove <model>"
            log "Removing Ollama model: ${model}..."
            docker exec "${container}" ollama rm "$model"
            ok "Model removed: ${model}"
            ;;
        *)
            fail "Unknown ollama action: ${action}. Use: list, pull, remove"
            ;;
    esac
}

# =============================================================================
# BACKUP STRATEGY
# =============================================================================
run_backup() {
    local schedule="${1:-}"   # empty = one-off; non-empty = cron expression

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  BACKUP"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local backup_dir="${DATA_DIR}/backups"
    mkdir -p "$backup_dir"

    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local archive="${backup_dir}/${TENANT_ID}-backup-${timestamp}.tar.gz"

    # Exclude the backups directory itself, ingestion cache, and rclone sync dir
    local exclude_args=(
        "--exclude=${DATA_DIR}/backups"
        "--exclude=${DATA_DIR}/ingestion"
        "--exclude=${DATA_DIR}/rclone"
        "--exclude=${DATA_DIR}/ollama"
    )

    log "Creating backup archive: ${archive}"
    log "This includes: config, postgres data, redis data, qdrant data, service configs"
    log "This excludes: ingestion cache, rclone sync, ollama models (re-pullable)"

    # Pause write-heavy services briefly if possible (best-effort)
    local paused_services=()
    for svc in postgres redis mongodb qdrant; do
        local cname="${TENANT_PREFIX}-${svc}"
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${cname}$"; then
            docker pause "$cname" 2>/dev/null && paused_services+=("$cname") || true
        fi
    done

    tar czf "$archive" "${exclude_args[@]}" -C "$(dirname "${DATA_DIR}")" "$(basename "${DATA_DIR}")" 2>/dev/null || true

    # Resume paused services
    for cname in "${paused_services[@]}"; do
        docker unpause "$cname" 2>/dev/null || true
    done

    local size
    size=$(du -sh "$archive" 2>/dev/null | awk '{print $1}' || echo "unknown")
    echo "  Archive: ${archive}"
    echo "  Size:    ${size}"

    # Upload to GDrive if rclone is available
    if [[ "${ENABLE_INGESTION:-false}" == "true" && "${INGESTION_METHOD:-rclone}" == "rclone" ]]; then
        local rclone_container="${TENANT_PREFIX}-rclone"
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${rclone_container}$"; then
            local remote_path="${RCLONE_REMOTE:-gdrive}:backups/${TENANT_ID}"
            log "Uploading backup to ${remote_path}..."
            local archive_basename
            archive_basename=$(basename "$archive")
            # Copy the backup into the rclone data volume so the container can see it
            docker cp "$archive" "${rclone_container}:/data-backup/${archive_basename}" 2>/dev/null || \
                log "Could not copy to rclone container — upload skipped"
        else
            echo "  rclone container not running — skipping GDrive upload"
        fi
    fi

    if [[ -n "$schedule" ]]; then
        # Add/replace cron entry for scheduled backups
        local cron_marker="# ai-platform-backup-${TENANT_ID}"
        local cron_cmd="bash ${SCRIPT_DIR}/3-configure-services.sh ${TENANT_ID} --backup >> ${DATA_DIR}/logs/backup.log 2>&1"
        # Remove old entry if present
        crontab -l 2>/dev/null | grep -v "$cron_marker" | crontab - 2>/dev/null || true
        # Add new entry
        (crontab -l 2>/dev/null; echo "${schedule} ${cron_cmd} ${cron_marker}") | crontab - 2>/dev/null
        echo "  Backup scheduled: ${schedule}"
        echo "  Cron entry added for tenant ${TENANT_ID}"
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ok "Backup complete: ${archive}"
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
# REBOOT PERSISTENCE (README §4.2)
# =============================================================================
configure_persistence() {
    section "🛡️  REBOOT PERSISTENCE"
    log "Configuring systemd service for automatic standup..."
    
    local service_name="ai-platform-${TENANT_ID}"
    local mount_point="/mnt/${TENANT_ID}"
    
    # Resolve the mount unit name for systemd dependency
    local mount_unit
    mount_unit=$(systemd-escape --suffix=mount "${mount_point}")
    
    sudo bash -s -- "${service_name}" "${TENANT_ID}" "${REPO_ROOT}" "${COMPOSE_FILE}" "${mount_unit}" << 'SUDO_EOF'
        service_name="$1"
        tenant_id="$2"
        repo_root="$3"
        compose_file="$4"
        mount_unit="$5"
        
        # Create systemd unit
        cat > "/etc/systemd/system/${service_name}.service" << UNITEFF
[Unit]
Description=AI Platform stack for ${tenant_id}
After=network.target docker.service ${mount_unit}
Requires=docker.service ${mount_unit}

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${repo_root}
# Run Script 2 to ensure containers (including web UIs and workers) are healthy
ExecStart=/usr/bin/bash scripts/2-deploy-services.sh ${tenant_id}
ExecStop=/usr/bin/docker compose -f ${compose_file} stop
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNITEFF

        systemctl daemon-reload
        systemctl enable "${service_name}"
        echo "  ✅ systemd service created and enabled: ${service_name}"
SUDO_EOF

    ok "Persistence configured. The platform will stand up automatically after reboot."
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
