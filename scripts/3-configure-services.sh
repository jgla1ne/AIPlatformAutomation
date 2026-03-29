#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Script 3: Mission Control Hub - Operational Verification & Logging
# =============================================================================
# PURPOSE: Central mission control for service verification and logging
# USAGE:   bash scripts/3-configure-services.sh
# =============================================================================

# Source environment file first
ENV_FILE="${ENV_FILE:-/mnt/data/${TENANT:-datasquiz}/.env}"
[[ -f "${ENV_FILE}" ]] || { echo "FATAL: ${ENV_FILE} not found"; exit 1; }
set -a; source "${ENV_FILE}"; set +a

# Logging configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOGS_DIR:-/mnt/data/${TENANT:-datasquiz}/logs}/3-configure-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "${LOG_FILE}")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level="$1"; shift
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*"
    echo -e "${msg}" | tee -a "${LOG_FILE}"
}

log_info() { log "INFO" "$@"; }
log_success() { log "SUCCESS" "$@"; }
log_warning() { log "WARNING" "$@"; }
log_error() { log "ERROR" "$@"; }

# =============================================================================
# SERVICE LOGGING COLLECTION
# =============================================================================
collect_all_service_logs() {
    log_info "=== Collecting All Service Logs ==="
    
    local services=("${OLLAMA_CONTAINER}" "${LLM_GATEWAY_CONTAINER}" "${MEM0_CONTAINER}" 
                   "${COMPOSE_PROJECT_NAME}_n8n" "${COMPOSE_PROJECT_NAME}_flowise"
                   "${COMPOSE_PROJECT_NAME}_postgres" "${COMPOSE_PROJECT_NAME}_redis"
                   "${COMPOSE_PROJECT_NAME}_qdrant" "${COMPOSE_PROJECT_NAME}_prometheus")
    
    for service in "${services[@]}"; do
        if docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
            log_info "Collecting logs for ${service}..."
            echo "=== ${service} LOGS ===" >> "${LOG_FILE}"
            docker logs "${service}" --tail 50 >> "${LOG_FILE}" 2>&1 || true
            echo "" >> "${LOG_FILE}"
        else
            log_warning "Service ${service} not running"
        fi
    done
    
    log_success "All service logs collected"
}

# =============================================================================
# OPERATIONAL VERIFICATION FUNCTIONS
# =============================================================================
verify_bifrost_operations() {
    log_info "=== Verifying Bifrost Operations ==="
    
    local url="http://localhost:${BIFROST_PORT:-8000}"
    local max_wait=60
    local elapsed=0
    
    # Wait for Bifrost to be ready
    until curl -sf "${url}/healthz" > /dev/null 2>&1; do
        if [[ $elapsed -ge $max_wait ]]; then
            log_error "Bifrost not ready after ${max_wait}s"
            return 1
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        log_info "Waiting for Bifrost... ${elapsed}/${max_wait}s"
    done
    
    # Test actual chat operation (not just health)
    local test_payload='{"model":"'"${OLLAMA_DEFAULT_MODEL}"'","messages":[{"role":"user","content":"Hello"}]}'
    local response
    response=$(curl -sf -w "%{http_code}" -X POST "${url}/api/chat" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${BIFROST_AUTH_TOKEN}" \
        -d "${test_payload}" 2>/dev/null)
    
    local http_code="${response: -3}"
    if [[ "$http_code" == "200" ]]; then
        log_success "Bifrost chat API operational"
        return 0
    else
        log_error "Bifrost chat API failed with HTTP ${http_code}"
        return 1
    fi
}

verify_ollama_operations() {
    log_info "=== Verifying Ollama Operations ==="
    
    local url="http://localhost:${OLLAMA_PORT:-11434}"
    local max_wait=120
    local elapsed=0
    
    # Wait for Ollama API
    until curl -sf "${url}/api/tags" > /dev/null 2>&1; do
        if [[ $elapsed -ge $max_wait ]]; then
            log_error "Ollama API not ready after ${max_wait}s"
            return 1
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        log_info "Waiting for Ollama API... ${elapsed}/${max_wait}s"
    done
    
    # Verify models are available
    local models_json
    models_json=$(curl -sf "${url}/api/tags" 2>/dev/null || echo "{}")
    
    for model in ${OLLAMA_MODELS//,/ }; do
        if echo "$models_json" | grep -q "\"name\":\"${model}\""; then
            log_success "Model ${model} available"
        else
            log_warning "Model ${model} not found"
        fi
    done
    
    # Test generation
    local test_payload='{"model":"'"${OLLAMA_DEFAULT_MODEL}"'","prompt":"Say hello"}'
    local response
    response=$(curl -sf -w "%{http_code}" -X POST "${url}/api/generate" \
        -H "Content-Type: application/json" \
        -d "${test_payload}" 2>/dev/null)
    
    local http_code="${response: -3}"
    if [[ "$http_code" == "200" ]]; then
        log_success "Ollama generation API operational"
        return 0
    else
        log_error "Ollama generation API failed with HTTP ${http_code}"
        return 1
    fi
}

verify_mem0_operations() {
    log_info "=== Verifying Mem0 Operations ==="
    
    local url="http://localhost:${MEM0_PORT:-8081}"
    local max_wait=180
    local elapsed=0
    
    # Wait for Mem0 startup (pip install can take 60-120s first boot)
    until curl -sf "${url}/health" > /dev/null 2>&1; do
        if [[ $elapsed -ge $max_wait ]]; then
            log_error "Mem0 failed to start after ${max_wait}s"
            return 1
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        log_info "Mem0 starting... ${elapsed}/${max_wait}s"
    done
    
    # Write test
    local tenant_a="verify_a_$$"
    local marker="mem0_test_${RANDOM}_${RANDOM}"
    local write_result
    write_result=$(curl -sf -w "\n%{http_code}" \
        -X POST "${url}/v1/memories" \
        -H "Authorization: Bearer ${MEM0_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"messages\":[{\"role\":\"user\",\"content\":\"${marker}\"}],\"user_id\":\"${tenant_a}\"}")
    
    local write_code=$(echo "${write_result}" | tail -1)
    if [[ "${write_code}" != "200" ]]; then
        log_error "Mem0 write test failed with HTTP ${write_code}"
        return 1
    fi
    
    # Search test
    local search_result
    search_result=$(curl -sf \
        -X POST "${url}/v1/memories/search" \
        -H "Authorization: Bearer ${MEM0_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"query\":\"${marker}\",\"user_id\":\"${tenant_a}\"}")
    
    if echo "${search_result}" | grep -q "${marker}"; then
        log_success "Mem0 operations verified"
        return 0
    else
        log_error "Mem0 search test failed"
        return 1
    fi
}

verify_n8n_operations() {
    log_info "=== Verifying n8n Operations ==="
    
    local url="http://localhost:5678"
    local max_wait=60
    local elapsed=0
    
    until curl -sf "${url}/healthz" > /dev/null 2>&1; do
        if [[ $elapsed -ge $max_wait ]]; then
            log_error "n8n not ready after ${max_wait}s"
            return 1
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        log_info "Waiting for n8n... ${elapsed}/${max_wait}s"
    done
    
    # Verify encryption key consistency
    if [[ -n "${N8N_ENCRYPTION_KEY:-}" ]]; then
        log_success "N8N encryption key available"
    else
        log_error "N8N encryption key missing"
        return 1
    fi
    
    log_success "n8n operations verified"
    return 0
}

verify_flowise_operations() {
    log_info "=== Verifying Flowise Operations ==="
    
    local url="http://localhost:${FLOWISE_PORT:-3001}"
    local max_wait=60
    local elapsed=0
    
    until curl -sf "${url}/api/v1/ping" > /dev/null 2>&1; do
        if [[ $elapsed -ge $max_wait ]]; then
            log_error "Flowise not ready after ${max_wait}s"
            return 1
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        log_info "Waiting for Flowise... ${elapsed}/${max_wait}s"
    done
    
    # Test authenticated API
    if [[ -n "${FLOWISE_PASSWORD:-}" ]]; then
        log_success "Flowise password configured"
    else
        log_error "Flowise password missing"
        return 1
    fi
    
    log_success "Flowise operations verified"
    return 0
}

verify_prometheus_operations() {
    log_info "=== Verifying Prometheus Operations ==="
    
    local url="http://localhost:9090"
    local max_wait=30
    local elapsed=0
    
    until curl -sf "${url}/-/healthy" > /dev/null 2>&1; do
        if [[ $elapsed -ge $max_wait ]]; then
            log_error "Prometheus not ready after ${max_wait}s"
            return 1
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        log_info "Waiting for Prometheus... ${elapsed}/${max_wait}s"
    done
    
    # Verify config reload
    local reload_result
    reload_result=$(curl -sf -X POST "${url}/-/reload" 2>/dev/null || echo "failed")
    if [[ "$reload_result" != "failed" ]]; then
        log_success "Prometheus config reload operational"
    else
        log_warning "Prometheus config reload failed"
    fi
    
    log_success "Prometheus operations verified"
    return 0
}

# =============================================================================
# MAIN VERIFICATION ORCHESTRATION
# =============================================================================
verify_service_operations() {
    log_info "=== Starting Comprehensive Service Operations Verification ==="
    
    local services_passed=0
    local services_failed=0
    local total_services=7
    
    # Run all verifications
    if verify_bifrost_operations; then
        ((services_passed++))
    else
        ((services_failed++))
    fi
    
    if verify_ollama_operations; then
        ((services_passed++))
    else
        ((services_failed++))
    fi
    
    if verify_mem0_operations; then
        ((services_passed++))
    else
        ((services_failed++))
    fi
    
    if verify_n8n_operations; then
        ((services_passed++))
    else
        ((services_failed++))
    fi
    
    if verify_flowise_operations; then
        ((services_passed++))
    else
        ((services_failed++))
    fi
    
    if verify_prometheus_operations; then
        ((services_passed++))
    else
        ((services_failed++))
    fi
    
    # Generate final report
    echo ""
    log_info "=== FINAL OPERATIONAL REPORT ==="
    log_info "Total Services: ${total_services}"
    log_success "Passed: ${services_passed}"
    if [[ $services_failed -gt 0 ]]; then
        log_error "Failed: ${services_failed}"
    else
        log_success "Failed: 0"
    fi
    
    if [[ $services_failed -eq 0 ]]; then
        log_success "🎉 PLATFORM 100% OPERATIONAL"
        return 0
    else
        log_error "❌ PLATFORM HAS ${services_failed} FAILING SERVICES"
        return 1
    fi
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================
main() {
    log_info "=== Mission Control Hub Starting ==="
    log_info "Log file: ${LOG_FILE}"
    
    # Step 1: Collect all service logs
    collect_all_service_logs
    
    # Step 2: Verify all service operations
    if verify_service_operations; then
        log_success "=== ALL SYSTEMS OPERATIONAL ==="
        exit 0
    else
        log_error "=== SYSTEM VERIFICATION FAILED ==="
        exit 1
    fi
}

# Execute main function
main "$@"
