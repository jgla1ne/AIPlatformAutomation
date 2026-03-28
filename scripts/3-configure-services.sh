#!/usr/bin/env bash
# scripts/3-configure-services.sh
# PRINCIPLE: Every function sources ENV_FILE. Nothing assumes ambient state.

set -euo pipefail

# Source env at script level
ENV_FILE="${ENV_FILE:-/mnt/ai-platform/.env}"
[[ -f "${ENV_FILE}" ]] || { echo "ERROR: ${ENV_FILE} not found"; exit 1; }
source "${ENV_FILE}"

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh" 2>/dev/null || true

log() {
    local level="$1"; shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*" | tee -a "${LOG_FILE:-/tmp/configure.log}"
}

# ============================================================
# INFRASTRUCTURE VERIFICATION
# Must pass before any service configuration begins
# ============================================================
verify_infrastructure() {
    source "${ENV_FILE}"
    log "INFO" "=== Verifying infrastructure health ==="
    
    local -a checks=(
        "PostgreSQL:docker exec ${POSTGRES_CONTAINER} pg_isready -U ${POSTGRES_USER} -q"
        "Redis:docker exec ${REDIS_CONTAINER} redis-cli ping | grep -q PONG"
        "Qdrant:curl -sf http://localhost:${QDRANT_PORT:-6333}/healthz > /dev/null"
        "Ollama:curl -sf http://localhost:${OLLAMA_PORT:-11434}/api/tags > /dev/null"
    )
    
    for check in "${checks[@]}"; do
        local name="${check%%:*}"
        local cmd="${check#*:}"
        local elapsed=0
        local max=180
        
        while ! eval "${cmd}" 2>/dev/null; do
            [[ ${elapsed} -ge ${max} ]] && {
                log "ERROR" "${name} not healthy after ${max}s — ABORTING"
                log "ERROR" "Container logs:"
                local cname
                case "${name}" in
                    PostgreSQL) cname="${POSTGRES_CONTAINER}" ;;
                    Redis)      cname="${REDIS_CONTAINER}" ;;
                    Qdrant)     cname="${QDRANT_CONTAINER}" ;;
                    Ollama)     cname="${OLLAMA_CONTAINER}" ;;
                esac
                docker logs "${cname}" --tail 30 2>&1 | while IFS= read -r l; do log "LOG" "  ${l}"; done
                return 1
            }
            sleep 5; elapsed=$((elapsed+5))
            log "INFO" "  Waiting for ${name}... ${elapsed}/${max}s"
        done
        log "SUCCESS" "${name} healthy"
    done
    
    # Verify models are available
    log "INFO" "Verifying Ollama models..."
    local tags
    tags=$(curl -sf "http://localhost:${OLLAMA_PORT:-11434}/api/tags")
    
    for model in "llama3.2" "nomic-embed-text"; do
        if echo "${tags}" | grep -q "${model}"; then
            log "SUCCESS" "Model ${model} available"
        else
            log "ERROR" "Model ${model} NOT available — this will cause Mem0 to fail"
            log "INFO" "Pulling ${model} now..."
            curl -sf -X POST "http://localhost:${OLLAMA_PORT:-11434}/api/pull" \
                -H "Content-Type: application/json" \
                -d "{\"name\": \"${model}\"}" \
                --max-time 1800 \
                --no-buffer | while IFS= read -r line; do
                    local status
                    status=$(echo "${line}" | python3 -c \
                        "import sys,json; print(json.loads(sys.stdin.read()).get('status',''))" \
                        2>/dev/null || true)
                    [[ -n "${status}" ]] && log "INFO" "  ${model}: ${status}"
                done
            
            # Verify pulled
            curl -sf "http://localhost:${OLLAMA_PORT:-11434}/api/tags" | grep -q "${model}" || {
                log "ERROR" "Failed to pull ${model} — cannot continue"
                return 1
            }
            log "SUCCESS" "Model ${model} pulled successfully"
        fi
    done
    
    log "SUCCESS" "Infrastructure verification complete"
}

# ============================================================
# QDRANT COLLECTION SETUP
# Mem0 requires this collection to exist before first write
# ============================================================
setup_qdrant_collections() {
    source "${ENV_FILE}"
    log "INFO" "=== Setting up Qdrant collections ==="
    
    local qdrant_url="http://localhost:${QDRANT_PORT:-6333}"
    local collection="${MEM0_COLLECTION:-ai_memory}"
    # nomic-embed-text produces 768-dimensional vectors
    local vector_size=768
    
    # Check existing
    local http_code
    http_code=$(curl -sf -o /dev/null -w "%{http_code}" \
        "${qdrant_url}/collections/${collection}" 2>/dev/null || echo "000")
    
    if [[ "${http_code}" == "200" ]]; then
        log "SUCCESS" "Collection '${collection}' already exists"
        # Verify vector size matches
        local existing_size
        existing_size=$(curl -sf "${qdrant_url}/collections/${collection}" | \
            python3 -c "import sys,json; \
            d=json.load(sys.stdin); \
            print(d['result']['config']['params']['vectors']['size'])" \
            2>/dev/null || echo "0")
        
        if [[ "${existing_size}" != "${vector_size}" ]]; then
            log "WARN" "Collection exists with size ${existing_size}, expected ${vector_size}"
            log "INFO" "Deleting and recreating collection..."
            curl -sf -X DELETE "${qdrant_url}/collections/${collection}" > /dev/null
            http_code="404"  # Force recreation
        fi
    fi
    
    if [[ "${http_code}" != "200" ]]; then
        log "INFO" "Creating collection '${collection}' (size=${vector_size}, distance=Cosine)..."
        
        local result
        result=$(curl -sf -w "\n%{http_code}" \
            -X PUT "${qdrant_url}/collections/${collection}" \
            -H "Content-Type: application/json" \
            -d "{
                \"vectors\": {
                    \"size\": ${vector_size},
                    \"distance\": \"Cosine\"
                },
                \"optimizers_config\": {
                    \"default_segment_number\": 2
                },
                \"replication_factor\": 1
            }")
        
        local create_code
        create_code=$(echo "${result}" | tail -1)
        local create_body
        create_body=$(echo "${result}" | head -1)
        
        [[ "${create_code}" != "200" ]] && {
            log "ERROR" "Failed to create collection — HTTP ${create_code}"
            log "ERROR" "Response: ${create_body}"
            return 1
        }
        log "SUCCESS" "Collection '${collection}' created"
    fi
    
    # Final verification
    curl -sf "${qdrant_url}/collections/${collection}" | \
        python3 -c "import sys,json; \
        d=json.load(sys.stdin); \
        s=d['result']['config']['params']['vectors']['size']; \
        print(f'  vectors.size={s}'); \
        assert s == ${vector_size}, f'Size mismatch: {s} != ${vector_size}'" || {
        log "ERROR" "Collection verification failed"
        return 1
    }
    
    log "SUCCESS" "Qdrant collection setup complete"
}

# ============================================================
# BIFROST CONFIGURATION AND OPERATIONAL VERIFICATION
# ============================================================
configure_bifrost() {
    source "${ENV_FILE}"
    log "INFO" "=== Configuring Bifrost ==="
    
    local url="http://localhost:${BIFROST_PORT:-8082}"
    local elapsed=0
    local max=120
    
    # Wait for container
    while ! curl -sf "${url}/healthz" > /dev/null 2>&1; do
        [[ ${elapsed} -ge ${max} ]] && {
            log "ERROR" "Bifrost /healthz timeout after ${max}s"
            log "ERROR" "=== Container status ==="
            docker inspect "${LLM_GATEWAY_CONTAINER}" \
                --format "Status: {{.State.Status}} ExitCode: {{.State.ExitCode}}" 2>/dev/null || true
            log "ERROR" "=== Container logs ==="
            docker logs "${LLM_GATEWAY_CONTAINER}" --tail 50 2>&1 | \
                while IFS= read -r l; do log "LOG" "  ${l}"; done
            log "ERROR" "=== Config file ==="
            if [[ -f "${CONFIG_DIR}/bifrost/config.yaml" ]]; then
                sed "s/${LLM_MASTER_KEY}/[MASKED]/g" \
                    "${CONFIG_DIR}/bifrost/config.yaml" | \
                    while IFS= read -r l; do log "LOG" "  ${l}"; done
            else
                log "ERROR" "Config file does not exist: ${CONFIG_DIR}/bifrost/config.yaml"
            fi
            return 1
        }
        sleep 5; elapsed=$((elapsed+5))
        log "INFO" "  Waiting for Bifrost /healthz... ${elapsed}/${max}s"
    done
    log "SUCCESS" "Bifrost /healthz OK (${elapsed}s)"
    
    # OPERATIONAL TEST — actual LLM routing
    # Per Bifrost docs: POST /api/chat with Authorization: Bearer <key>
    # Model format: "provider/model" e.g. "ollama/llama3.2"
    log "INFO" "Testing Bifrost LLM routing (operational test)..."
    
    local route_response
    local route_code
    route_response=$(curl -sf -w "\n%{http_code}" \
        -X POST "${url}/api/chat" \
        -H "Authorization: Bearer ${LLM_MASTER_KEY}" \
        -H "Content-Type: application/json" \
        --max-time 30 \
        -d '{
            "model": "ollama/llama3.2",
            "messages": [
                {"role": "user", "content": "Reply with exactly one word: operational"}
            ],
            "stream": false
        }' 2>&1) || true
    
    route_code=$(echo "${route_response}" | tail -1)
    local route_body
    route_body=$(echo "${route_response}" | head -1)
    
    if [[ "${route_code}" == "200" ]]; then
        local content
        content=$(echo "${route_body}" | \
            python3 -c "import sys,json; \
            d=json.load(sys.stdin); \
            print(d.get('message',{}).get('content','<empty>'))" \
            2>/dev/null || echo "${route_body}")
        log "SUCCESS" "Bifrost routing operational — response: ${content}"
    else
        log "ERROR" "Bifrost routing FAILED — HTTP ${route_code}"
        log "ERROR" "Response: ${route_body}"
        log "ERROR" "=== Bifrost logs ==="
        docker logs "${LLM_GATEWAY_CONTAINER}" --tail 30 2>&1 | \
            while IFS= read -r l; do log "LOG" "  ${l}"; done
        return 1
    fi
    
    update_env "BIFROST_STATUS" "operational"
    log "SUCCESS" "Bifrost fully configured and operational"
}

# ============================================================
# MEM0 CONFIGURATION AND OPERATIONAL VERIFICATION
# ============================================================
configure_mem0() {
    source "${ENV_FILE}"
    log "INFO" "=== Configuring Mem0 ==="
    
    local url="http://localhost:${MEM0_PORT:-8081}"
    local elapsed=0
    # First boot: pip install takes 2-4 minutes
    local max=480
    
    log "INFO" "Waiting for Mem0 health (first boot may take up to ${max}s for pip install)..."
    
    while true; do
        local health_response
        health_response=$(curl -sf "${url}/health" 2>/dev/null || echo "")
        
        if echo "${health_response}" | grep -qi "ok\|healthy\|true"; then
            log "SUCCESS" "Mem0 /health OK (${elapsed}s)"
            break
        fi
        
        [[ ${elapsed} -ge ${max} ]] && {
            log "ERROR" "Mem0 /health timeout after ${max}s"
            log "ERROR" "=== Container logs ==="
            docker logs "${MEM0_CONTAINER}" --tail 50 2>&1 | \
                while IFS= read -r l; do log "LOG" "  ${l}"; done
            return 1
        }
        
        sleep 10; elapsed=$((elapsed+10))
        
        # Show live container output every 30s
        if [[ $((elapsed % 30)) -eq 0 ]]; then
            log "INFO" "  Mem0 still initializing... ${elapsed}/${max}s"
            docker logs "${MEM0_CONTAINER}" --tail 3 2>&1 | \
                while IFS= read -r l; do log "LOG" "  ${l}"; done
        fi
    done
    
    # OPERATIONAL TEST 1 — Write memory
    local tenant_a="test_tenant_$(date +%s)_a"
    local test_phrase="platform_operational_verify_$(date +%s)"
    
    log "INFO" "Testing Mem0 write (tenant: ${tenant_a})..."
    
    local write_response
    local write_code
    write_response=$(curl -sf -w "\n%{http_code}" \
        -X POST "${url}/v1/memories" \
        -H "Authorization: Bearer ${MEM0_API_KEY}" \
        -H "Content-Type: application/json" \
        --max-time 60 \
        -d "{
            \"messages\": [
                {\"role\": \"user\", \"content\": \"${test_phrase}\"}
            ],
            \"user_id\": \"${tenant_a}\"
        }")
    
    write_code=$(echo "${write_response}" | tail -1)
    local write_body
    write_body=$(echo "${write_response}" | head -1)
    
    if [[ "${write_code}" != "200" ]]; then
        log "ERROR" "Mem0 write FAILED — HTTP ${write_code}"
        log "ERROR" "Body: ${write_body}"
        log "ERROR" "=== Diagnostics ==="
        log "ERROR" "Qdrant collection status:"
        curl -sf "http://localhost:${QDRANT_PORT:-6333}/collections/${MEM0_COLLECTION:-ai_memory}" \
            | python3 -m json.tool 2>/dev/null || echo "Cannot reach Qdrant"
        log "ERROR" "Ollama nomic-embed-text status:"
        curl -sf "http://localhost:${OLLAMA_PORT:-11434}/api/tags" | \
            python3 -c "import sys,json; \
            models=[m['name'] for m in json.load(sys.stdin)['models']]; \
            print([m for m in models if 'nomic' in m])" 2>/dev/null || true
        log "ERROR" "Mem0 container logs:"
        docker logs "${MEM0_CONTAINER}" --tail 30 2>&1 | \
            while IFS= read -r l; do log "LOG" "  ${l}"; done
        return 1
    fi
    log "SUCCESS" "Mem0 write OK — HTTP ${write_code}"
    
    # Allow vector indexing
    sleep 3
    
    # OPERATIONAL TEST 2 — Search (same tenant must find result)
    log "INFO" "Testing Mem0 search (same tenant)..."
    
    local search_response
    search_response=$(curl -sf \
        -X POST "${url}/v1/memories/search" \
        -H "Authorization: Bearer ${MEM0_API_KEY}" \
        -H "Content-Type: application/json" \
        --max-time 30 \
        -d "{\"query\": \"${test_phrase}\", \"user_id\": \"${tenant_a}\"}" \
        2>/dev/null || echo '{"results":[]}')
    
    local result_count
    result_count=$(echo "${search_response}" | \
        python3 -c "import sys,json; \
        d=json.load(sys.stdin); \
        print(len(d.get('results', d.get('memories', []))))" \
        2>/dev/null || echo "0")
    
    if [[ "${result_count}" -eq 0 ]]; then
        log "ERROR" "Mem0 search returned 0 results — write/search pipeline broken"
        log "ERROR" "Search response: ${search_response}"
        return 1
    fi
    log "SUCCESS" "Mem0 search found ${result_count} result(s)"
    
    # OPERATIONAL TEST 3 — Tenant isolation (different tenant must find NOTHING)
    log "INFO" "Testing Mem0 tenant isolation..."
    
    local tenant_b="test_tenant_$(date +%s)_b"
    local isolation_response
    isolation_response=$(curl -sf \
        -X POST "${url}/v1/memories/search" \
        -H "Authorization: Bearer ${MEM0_API_KEY}" \
        -H "Content-Type: application/json" \
        --max-time 30 \
        -d "{\"query\": \"${test_phrase}\", \"user_id\": \"${tenant_b}\"}" \
        2>/dev/null || echo '{"results":[{"ISOLATION_CHECK_FAILED":true}]}')
    
    local isolation_count
    isolation_count=$(echo "${isolation_response}" | \
        python3 -c "import sys,json; \
        d=json.load(sys.stdin); \
        print(len(d.get('results', d.get('memories', []))))" \
        2>/dev/null || echo "1")
    
    if [[ "${isolation_count}" -ne 0 ]]; then
        log "ERROR" "CRITICAL SECURITY FAILURE: Tenant isolation broken"
        log "ERROR" "Data from ${tenant_a} visible to ${tenant_b}"
        log "ERROR" "Response: ${isolation_response}"
        return 1
    fi
    log "SUCCESS" "Tenant isolation verified — ${tenant_b} sees 0 results"
    
    update_env "MEM0_STATUS" "operational"
    log "SUCCESS" "Mem0 fully operational"
}

# ============================================================
# N8N CONFIGURATION
# ============================================================
configure_n8n() {
    source "${ENV_FILE}"
    log "INFO" "=== Configuring n8n ==="
    
    local url="http://localhost:${N8N_PORT:-5678}"
    local elapsed=0
    local max=180
    
    while ! curl -sf "${url}/healthz" | grep -q "ok" 2>/dev/null; do
        [[ ${elapsed} -ge ${max} ]] && {
            log "ERROR" "n8n /healthz timeout after ${max}s"
            docker logs "${N8N_CONTAINER:-${PROJECT_NAME}-n8n}" --tail 20 2>&1 | \
                while IFS= read -r l; do log "LOG" "  ${l}"; done
            return 1
        }
        sleep 5; elapsed=$((elapsed+5))
        log "INFO" "  Waiting for n8n... ${elapsed}/${max}s"
    done
    
    # Verify encryption key is the same one n8n started with
    local container_key
    container_key=$(docker exec "${N8N_CONTAINER:-${PROJECT_NAME}-n8n}" \
        env | grep N8N_ENCRYPTION_KEY | cut -d= -f2- 2>/dev/null || echo "")
    
    if [[ "${container_key}" != "${N8N_ENCRYPTION_KEY}" ]]; then
        log "ERROR" "N8N_ENCRYPTION_KEY mismatch between .env and running container"
        log "ERROR" "This means credentials will be corrupted"
        log "ERROR" "Container key: ${container_key:0:8}..."
        log "ERROR" "ENV file key:   ${N8N_ENCRYPTION_KEY:0:8}..."
        return 1
    fi
    log "SUCCESS" "n8n encryption key consistent"
    
    # Verify webhook endpoint
    local webhook_code
    webhook_code=$(curl -sf -o /dev/null -w "%{http_code}" \
        "${url}/webhook-test/" 2>/dev/null || echo "000")
    # 404 is expected for non-existent webhook, 200 means it's routing correctly
    [[ "${webhook_code}" =~ ^(200|404)$ ]] && \
        log "SUCCESS" "n8n webhook routing operational (HTTP ${webhook_code})" || \
        log "WARN" "n8n webhook routing returned HTTP ${webhook_code}"
    
    log "SUCCESS" "n8n configured"
}

# ============================================================
# FLOWISE CONFIGURATION
# ============================================================
configure_flowise() {
    source "${ENV_FILE}"
    log "INFO" "=== Configuring Flowise ==="
    
    local url="http://localhost:${FLOWISE_PORT:-3001}"
    local elapsed=0
    local max=180
    
    while ! curl -sf "${url}/api/v1/ping" | grep -q "pong" 2>/dev/null; do
        [[ ${elapsed} -ge ${max} ]] && {
            log "ERROR" "Flowise /api/v1/ping timeout after ${max}s"
            docker logs "${FLOWISE_CONTAINER:-${PROJECT_NAME}-flowise}" --tail 20 2>&1 | \
                while IFS= read -r l; do log "LOG" "  ${l}"; done
            return 1
        }
        sleep 5; elapsed=$((elapsed+5))
        log "INFO" "  Waiting for Flowise... ${elapsed}/${max}s"
    done
    log "SUCCESS" "Flowise /api/v1/ping OK"
    
    # Verify authenticated API works (requires FLOWISE_PASSWORD in container env)
    local auth_code
    auth_code=$(curl -sf -o /dev/null -w "%{http_code}" \
        -u "${FLOWISE_USERNAME}:${FLOWISE_PASSWORD}" \
        "${url}/api/v1/chatflows" 2>/dev/null || echo "000")
    
    if [[ "${auth_code}" == "200" ]]; then
        log "SUCCESS" "Flowise authenticated API operational"
    else
        log "ERROR" "Flowise authenticated API FAILED — HTTP ${auth_code}"
        log "ERROR" "Check FLOWISE_PASSWORD is passed to container environment"
        log "ERROR" "Container env:"
        docker exec "${FLOWISE_CONTAINER:-${PROJECT_NAME}-flowise}" env | \
            grep -E "FLOWISE|DATABASE" 2>/dev/null | \
            while IFS= read -r l; do log "LOG" "  ${l}"; done
        return 1
    fi
    
    log "SUCCESS" "Flowise configured"
}

# ============================================================
# PROMETHEUS CONFIGURATION
# ============================================================
configure_prometheus() {
    source "${ENV_FILE}"
    log "INFO" "=== Configuring Prometheus ==="
    
    # Write prometheus.yml with container-name targets (not localhost)
    # From inside Prometheus container, other services are reachable by container name
    local prom_config="${CONFIG_DIR}/prometheus/prometheus.yml"
    mkdir -p "${CONFIG_DIR}/prometheus"
    
    cat > "${prom_config}" << PROMEOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  scrape_timeout: 10s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'caddy'
    static_configs:
      - targets: ['${CADDY_CONTAINER:-${PROJECT_NAME}-caddy}:2019']
    metrics_path: /metrics

  - job_name: 'node'
    static_configs:
      - targets: ['${PROJECT_NAME}-node-exporter:9100']

  - job_name: 'ollama'
    static_configs:
      - targets: ['${OLLAMA_CONTAINER}:${OLLAMA_PORT:-11434}']
    metrics_path: /metrics

  - job_name: 'qdrant'
    static_configs:
      - targets: ['${QDRANT_CONTAINER}:6333']
    metrics_path: /metrics
PROMEOF
    
    # Reload prometheus config
    local prom_url="http://localhost:${PROMETHEUS_PORT:-9090}"
    local elapsed=0
    local max=60
    
    while ! curl -sf "${prom_url}/-/healthy" > /dev/null 2>&1; do
        [[ ${elapsed} -ge ${max} ]] && {
            log "WARN" "Prometheus not healthy — skipping reload"
            return 0
        }
        sleep 5; elapsed=$((elapsed+5))
    done
    
    # Reload config
    curl -sf -X POST "${prom_url}/-/reload" > /dev/null 2>&1 && \
        log "SUCCESS" "Prometheus config reloaded" || \
        log "WARN" "Prometheus reload returned error (may need --web.enable-lifecycle flag)"
    
    # Check targets (allow some to be down — n8n/flowise may not expose metrics)
    sleep 5
    local targets_response
    targets_response=$(curl -sf "${prom_url}/api/v1/targets" 2>/dev/null || echo '{"data":{"activeTargets":[]}}')
    local active_count
    active_count=$(echo "${targets_response}" | \
        python3 -c "import sys,json; \
        t=json.load(sys.stdin)['data']['activeTargets']; \
        up=[x for x in t if x['health']=='up']; \
        print(f'{len(up)}/{len(t)} targets up')" \
        2>/dev/null || echo "unknown")
    
    log "SUCCESS" "Prometheus configured — ${active_count}"
}

# ============================================================
# FINAL OPERATIONAL SUMMARY
# ============================================================
print_summary() {
    source "${ENV_FILE}"
    log "INFO" "=== Platform Operational Summary ==="
    
    local pass=0
    local fail=0
    
    check_service() {
        local name="$1"
        local cmd="$2"
        if eval "${cmd}" > /dev/null 2>&1; then
            log "SUCCESS" "✅ ${name}"
            pass=$((pass+1))
        else
            log "ERROR" "❌ ${name}"
            fail=$((fail+1))
        fi
    }
    
    check_service "PostgreSQL" \
        "docker exec ${POSTGRES_CONTAINER} pg_isready -U ${POSTGRES_USER} -q"
    check_service "Redis" \
        "docker exec ${REDIS_CONTAINER} redis-cli ping | grep -q PONG"
    check_service "Qdrant" \
        "curl -sf http://localhost:${QDRANT_PORT:-6333}/healthz"
    check_service "Ollama (llama3.2)" \
        "curl -sf http://localhost:${OLLAMA_PORT:-11434}/api/tags | grep -q llama3.2"
    check_service "Ollama (nomic-embed-text)" \
        "curl -sf http://localhost:${OLLAMA_PORT:-11434}/api/tags | grep -q nomic-embed-text"
    check_service "Bifrost /healthz" \
        "curl -sf http://localhost:${BIFROST_PORT}/healthz"
    check_service "Bifrost routing" \
        "curl -sf -X POST http://localhost:${BIFROST_PORT}/api/chat \
         -H 'Authorization: Bearer ${LLM_MASTER_KEY}' \
         -H 'Content-Type: application/json' --max-time 30 \
         -d '{\"model\":\"ollama/llama3.2\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"stream\":false}' \
         | grep -q content"
    check_service "Mem0 /health" \
        "curl -sf http://localhost:${MEM0_PORT}/health | grep -qi ok"
    check_service "Mem0 write" \
        "curl -sf -X POST http://localhost:${MEM0_PORT}/v1/memories \
         -H 'Authorization: Bearer ${MEM0_API_KEY}' \
         -H 'Content-Type: application/json' --max-time 30 \
         -d '{\"messages\":[{\"role\":\"user\",\"content\":\"summary_check\"}],\"user_id\":\"summary_test\"}' \
         | grep -q id"
    check_service "n8n /healthz" \
        "curl -sf http://localhost:${N8N_PORT}/healthz | grep -q ok"
    check_service "Flowise /api/v1/ping" \
        "curl -sf http://localhost:${FLOWISE_PORT}/api/v1/ping | grep -q pong"
    check_service "Flowise authenticated" \
        "curl -sf -u ${FLOWISE_USERNAME}:${FLOWISE_PASSWORD} \
         http://localhost:${FLOWISE_PORT}/api/v1/chatflows | grep -q '\[\|chatflows'"
    check_service "OpenWebUI" \
        "curl -sf http://localhost:${OPENWEBUI_PORT}/ | grep -qi 'open webui\|html'"
    check_service "Prometheus /-/healthy" \
        "curl -sf http://localhost:${PROMETHEUS_PORT:-9090}/-/healthy"
    check_service "Caddy" \
        "curl -sf http://localhost:2019/metrics | grep -q caddy"
    
    echo ""
    log "INFO" "Results: ${pass} passed, ${fail} failed"
    
    if [[ ${fail} -eq 0 ]]; then
        log "SUCCESS" "🎉 PLATFORM 100% OPERATIONAL"
        log "INFO" "Dashboard: https://${DOMAIN}"
        log "INFO" "OpenWebUI: https://chat.${DOMAIN}"
        log "INFO" "n8n:       https://n8n.${DOMAIN}"
        log "INFO" "Flowise:   https://flowise.${DOMAIN}"
    else
        log "ERROR" "❌ ${fail} service(s) not operational — check logs above"
        return 1
    fi
}

# ============================================================
# MAIN — Strict dependency order. No skipping. No assuming.
# ============================================================
main() {
    source "${ENV_FILE}"
    log "INFO" "Starting platform configuration — $(date)"
    log "INFO" "Project: ${PROJECT_NAME}"
    log "INFO" "Domain:  ${DOMAIN}"
    log "INFO" "Data:    ${DATA_DIR}"
    
    verify_infrastructure     || { log "ERROR" "Infrastructure failed — ABORT"; exit 1; }
    setup_qdrant_collections  || { log "ERROR" "Qdrant setup failed — ABORT"; exit 1; }
    configure_bifrost         || { log "ERROR" "Bifrost failed — ABORT"; exit 1; }
    configure_mem0            || { log "ERROR" "Mem0 failed — ABORT"; exit 1; }
    configure_n8n             || { log "ERROR" "n8n failed — ABORT"; exit 1; }
    configure_flowise         || { log "ERROR" "Flowise failed — ABORT"; exit 1; }
    configure_prometheus      || { log "ERROR" "Prometheus failed — ABORT"; exit 1; }
    configure_caddy           || { log "ERROR" "Caddy failed — ABORT"; exit 1; }
    print_summary             || exit 1
}

# Call main with all arguments
main "$@"
