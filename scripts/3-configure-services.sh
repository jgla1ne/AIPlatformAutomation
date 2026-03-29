#!/usr/bin/env bash
# =============================================================================
# Script 3: Mission Control Hub - BULLETPROOF v4.0
# =============================================================================
# PURPOSE: Health verification, model pulls, and operational testing
# USAGE:   sudo bash scripts/3-configure-services.sh [tenant_id]
# =============================================================================

set -euo pipefail

# Claude Audit Fix 8: TENANT_ID fallback
TENANT_ID=${1:-"default"}

# Basic Logging Functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
log() { echo -e "${CYAN}[INFO]${NC}    $1"; }
ok() { echo -e "${GREEN}[OK]${NC}      $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}    $*"; }
fail() { echo -e "${RED}[FAIL]${NC}    $*"; }

# Claude Audit: Global error counter
ERRORS=0

# Claude Audit: wait_for_healthy with timeout and logging
wait_for_healthy() {
    local container=$1
    local max_wait=${2:-300}
    local elapsed=0
    
    log "Waiting for ${container} to be healthy (max ${max_wait}s)..."
    
    while [ $elapsed -lt $max_wait ]; do
        status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "starting")
        case "$status" in
            "healthy")
                ok "${container} healthy after ${elapsed}s"
                return 0 ;;
            "unhealthy")
                fail "${container} entered unhealthy state"
                docker logs "$container" --tail 30
                return 1 ;;
        esac
        sleep 5
        elapsed=$((elapsed + 5))
        echo "⏳ ${container}: ${status} (${elapsed}/${max_wait}s)"
    done
    
    fail "Timeout: ${container} not healthy after ${max_wait}s"
    docker logs "$container" --tail 30
    return 1
}

# Claude Audit: Load environment from .env
load_env() {
    local env_file="/mnt/data/${TENANT_ID}/.env"
    if [[ ! -f "${env_file}" ]]; then
        fail "Environment file not found: ${env_file}. Run Script 1 first."
    fi
    
    log "Loading environment from ${env_file}..."
    source "${env_file}"
}

# Claude Audit: Pull Ollama models after health verification
pull_ollama_models() {
    log "Pulling Ollama models..."
    
    # Wait for Ollama to be healthy
    wait_for_healthy "${OLLAMA_CONTAINER_NAME}" || ((ERRORS++))
    
    # Pull default model
    log "Pulling model: ${OLLAMA_DEFAULT_MODEL}"
    if docker exec "${OLLAMA_CONTAINER_NAME}" ollama pull "${OLLAMA_DEFAULT_MODEL}"; then
        ok "Model ${OLLAMA_DEFAULT_MODEL} pulled successfully"
    else
        fail "Failed to pull model ${OLLAMA_DEFAULT_MODEL}"
        ((ERRORS++))
    fi
}

# Claude Audit: Verify Bifrost with provider-prefixed model
verify_bifrost() {
    log "Verifying Bifrost LLM proxy..."
    
    wait_for_healthy "${BIFROST_CONTAINER_NAME}" || ((ERRORS++))
    
    # Test with provider-prefixed model format
    local response
    response=$(curl -s -w "%{http_code}" -o /tmp/bifrost_response.json \
        -H "Authorization: Bearer ${BIFROST_AUTH_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"ollama/${OLLAMA_DEFAULT_MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}],\"max_tokens\":10}" \
        "http://localhost:${BIFROST_HOST_PORT}/v1/chat/completions")
    
    if [[ "$response" == "200" ]]; then
        ok "Bifrost API responding correctly"
        log "Response: $(cat /tmp/bifrost_response.json | jq -r '.choices[0].message.content' 2>/dev/null || echo 'parsed')"
    else
        fail "Bifrost API returned HTTP $response"
        ((ERRORS++))
    fi
}

# Claude Audit: Verify Mem0 with trailing slash endpoints
verify_mem0() {
    log "Verifying Mem0 memory layer..."
    
    wait_for_healthy "${MEM0_CONTAINER_NAME}" || ((ERRORS++))
    
    # Test memory creation with trailing slash
    local create_response
    create_response=$(curl -s -w "%{http_code}" -o /tmp/mem0_create.json \
        -H "Authorization: Bearer ${MEM0_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"messages\":[{\"role\":\"user\",\"content\":\"Test memory\"}]}" \
        "http://localhost:${MEM0_HOST_PORT}/v1/memories/")
    
    if [[ "$create_response" == "200" ]]; then
        ok "Mem0 memory creation successful"
    else
        fail "Mem0 memory creation failed with HTTP $create_response"
        ((ERRORS++))
    fi
    
    # Test memory search with trailing slash
    local search_response
    search_response=$(curl -s -w "%{http_code}" -o /tmp/mem0_search.json \
        -H "Authorization: Bearer ${MEM0_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"query\":\"test\"}" \
        "http://localhost:${MEM0_HOST_PORT}/v1/memories/search/")
    
    if [[ "$search_response" == "200" ]]; then
        ok "Mem0 memory search successful"
    else
        fail "Mem0 memory search failed with HTTP $search_response"
        ((ERRORS++))
    fi
}

# Claude Audit: Verify Flowise with correct endpoint
verify_flowise() {
    log "Verifying Flowise AI workflow builder..."
    
    wait_for_healthy "${FLOWISE_CONTAINER_NAME}" || ((ERRORS++))
    
    local response
    response=$(curl -s -w "%{http_code}" -o /tmp/flowise_response.json \
        "http://localhost:${FLOWISE_HOST_PORT}/api/v1/version")
    
    if [[ "$response" == "200" ]]; then
        ok "Flowise API responding correctly"
        log "Version: $(cat /tmp/flowise_response.json | jq -r '.version' 2>/dev/null || echo 'parsed')"
    else
        fail "Flowise API returned HTTP $response"
        ((ERRORS++))
    fi
}

# Claude Audit: Verify N8N with correct endpoint
verify_n8n() {
    log "Verifying N8N workflow automation..."
    
    wait_for_healthy "${N8N_CONTAINER_NAME}" || ((ERRORS++))
    
    local response
    response=$(curl -s -w "%{http_code}" -o /tmp/n8n_response.json \
        "http://localhost:${N8N_HOST_PORT}/healthz")
    
    if [[ "$response" == "200" ]]; then
        ok "N8N health check successful"
    else
        fail "N8N health check failed with HTTP $response"
        ((ERRORS++))
    fi
}

# Claude Audit: Verify Prometheus with correct endpoint
verify_prometheus() {
    log "Verifying Prometheus metrics collection..."
    
    wait_for_healthy "${PROMETHEUS_CONTAINER_NAME}" || ((ERRORS++))
    
    local response
    response=$(curl -s -w "%{http_code}" -o /tmp/prometheus_response.json \
        "http://localhost:${PROMETHEUS_HOST_PORT}/-/healthy")
    
    if [[ "$response" == "200" ]]; then
        ok "Prometheus health check successful"
    else
        fail "Prometheus health check failed with HTTP $response"
        ((ERRORS++))
    fi
}

# Claude Audit: Verify Grafana with correct endpoint
verify_grafana() {
    log "Verifying Grafana monitoring..."
    
    wait_for_healthy "${GRAFANA_CONTAINER_NAME}" || ((ERRORS++))
    
    local response
    response=$(curl -s -w "%{http_code}" -o /tmp/grafana_response.json \
        "http://localhost:${GRAFANA_HOST_PORT}/api/health")
    
    if [[ "$response" == "200" ]]; then
        ok "Grafana health check successful"
    else
        fail "Grafana health check failed with HTTP $response"
        ((ERRORS++))
    fi
}

# Claude Audit: Aggregate logs for diagnostics
aggregate_logs() {
    log "Aggregating service logs for diagnostics..."
    
    local log_dir="/mnt/data/${TENANT_ID}/logs"
    mkdir -p "${log_dir}"
    
    for container in "${BIFROST_CONTAINER_NAME}" "${OLLAMA_CONTAINER_NAME}" "${MEM0_CONTAINER_NAME}" "${QDRANT_CONTAINER_NAME}" "${FLOWISE_CONTAINER_NAME}" "${N8N_CONTAINER_NAME}" "${GRAFANA_CONTAINER_NAME}" "${PROMETHEUS_CONTAINER_NAME}"; do
        if docker ps --format "table {{.Names}}" | grep -q "^${container}$"; then
            docker logs "$container" --tail 100 > "${log_dir}/${container}.log" 2>/dev/null || true
            log "Logs saved: ${log_dir}/${container}.log"
        fi
    done
    
    ok "Log aggregation complete"
}

# Claude Audit: Final operational report
final_report() {
    log "Generating final operational report..."
    
    echo ""
    echo "=========================================="
    echo "🎉 PLATFORM OPERATIONAL REPORT"
    echo "=========================================="
    echo "Tenant: ${TENANT_ID}"
    echo "Errors: ${ERRORS}"
    echo ""
    
    if [[ $ERRORS -eq 0 ]]; then
        echo "✅ ALL SERVICES OPERATIONAL"
        echo ""
        echo "Service Access URLs:"
        echo "  Bifrost LLM Proxy: http://localhost:${BIFROST_HOST_PORT}"
        echo "  Ollama Inference: http://localhost:${OLLAMA_HOST_PORT}"
        echo "  Mem0 Memory: http://localhost:${MEM0_HOST_PORT}"
        echo "  Flowise Workflows: http://localhost:${FLOWISE_HOST_PORT}"
        echo "  N8N Automation: http://localhost:${N8N_HOST_PORT}"
        echo "  Grafana Monitoring: http://localhost:${GRAFANA_HOST_PORT}"
        echo "  Prometheus Metrics: http://localhost:${PROMETHEUS_HOST_PORT}"
        echo ""
        echo "🚀 PLATFORM 100% OPERATIONAL"
    else
        echo "❌ PLATFORM HAS ${ERRORS} ERRORS"
        echo ""
        echo "Check logs in: /mnt/data/${TENANT_ID}/logs/"
        echo "Run individual verification commands for details."
    fi
    
    echo "=========================================="
}

main() {
    log "Starting Mission Control for tenant '${TENANT_ID}'..."
    
    # Load environment variables
    load_env
    
    # Execute verification sequence
    pull_ollama_models
    verify_bifrost
    verify_mem0
    verify_flowise
    verify_n8n
    verify_prometheus
    verify_grafana
    
    # Aggregate logs for diagnostics
    aggregate_logs
    
    # Generate final report
    final_report
    
    # Claude Audit: Exit with error code if failures
    if [[ $ERRORS -gt 0 ]]; then
        log "Mission Control completed with ${ERRORS} errors"
        exit 1
    else
        ok "Mission Control completed successfully"
        exit 0
    fi
}

# Call main function
main "$@"
