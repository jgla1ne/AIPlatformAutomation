#!/usr/bin/env bash
# scripts/3-configure-services.sh
# PRINCIPLE: Every function sources ENV_FILE. Nothing assumes ambient state.

set -euo pipefail

# Source env — every function re-sources to guarantee variable availability
ENV_FILE="${ENV_FILE:-/mnt/ai-platform/.env}"
[[ -f "${ENV_FILE}" ]] || { echo "FATAL: ${ENV_FILE} not found"; exit 1; }
set -a; source "${ENV_FILE}"; set +a

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_DIR:-/mnt/ai-platform/logs}/3-configure-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "${LOG_FILE}")"

log() {
    local level="$1"; shift
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*"
    echo "${msg}" | tee -a "${LOG_FILE}"
}

wait_for_url() {
    local name="$1"
    local url="$2"
    local max="${3:-120}"
    local pattern="${4:-}"
    local elapsed=0
    
    log "INFO" "Waiting for ${name} at ${url}..."
    until curl -sf --max-time 10 "${url}" 2>/dev/null | \
          { [[ -n "${pattern}" ]] && grep -qi "${pattern}" || cat > /dev/null; }; do
        [[ ${elapsed} -ge ${max} ]] && {
            log "ERROR" "${name} timeout after ${max}s (url: ${url})"
            return 1
        }
        sleep 5; elapsed=$((elapsed+5))
        [[ $((elapsed % 30)) -eq 0 ]] && log "INFO" "  Still waiting for ${name}... ${elapsed}/${max}s"
    done
    log "SUCCESS" "${name} ready after ${elapsed}s"
}

# ============================================================
# STEP 1: Verify infrastructure before configuring anything
# ============================================================
verify_infrastructure() {
    set -a; source "${ENV_FILE}"; set +a
    log "INFO" "=== Step 1: Infrastructure Verification ==="
    
    # PostgreSQL
    local elapsed=0
    until docker exec "${POSTGRES_CONTAINER}" pg_isready \
          -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -q 2>/dev/null; do
        [[ ${elapsed} -ge 120 ]] && {
            log "ERROR" "PostgreSQL not ready after 120s"
            docker logs "${POSTGRES_CONTAINER}" --tail 20 2>&1 | \
                while IFS= read -r l; do log "LOG" "${l}"; done
            return 1
        }
        sleep 5; elapsed=$((elapsed+5))
    done
    log "SUCCESS" "PostgreSQL ready"
    
    # Redis
    elapsed=0
    until docker exec "${REDIS_CONTAINER}" redis-cli ping 2>/dev/null | grep -q PONG; do
        [[ ${elapsed} -ge 60 ]] && { log "ERROR" "Redis not ready"; return 1; }
        sleep 5; elapsed=$((elapsed+5))
    done
    log "SUCCESS" "Redis ready"
    
    # Qdrant
    wait_for_url "Qdrant" "http://localhost:${QDRANT_PORT:-6333}/healthz" 120 || return 1
    
    # Ollama — verify both models present
    wait_for_url "Ollama" "http://localhost:${OLLAMA_PORT:-11434}/api/tags" 180 || return 1
    
    local tags
    tags=$(curl -sf "http://localhost:${OLLAMA_PORT:-11434}/api/tags")
    
    for model in "llama3.2" "nomic-embed-text"; do
        if echo "${tags}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
names = [m['name'] for m in data.get('models', [])]
exit(0 if any('${model}' in n for n in names) else 1)
" 2>/dev/null; then
            log "SUCCESS" "Ollama model '${model}' confirmed present"
        else
            log "ERROR" "Ollama model '${model}' MISSING — pulling now..."
            curl -sf -X POST "http://localhost:${OLLAMA_PORT:-11434}/api/pull" \
                -H "Content-Type: application/json" \
                -d "{\"name\": \"${model}\"}" \
                --max-time 1800 --no-buffer | \
            while IFS= read -r line; do
                python3 -c "import sys,json; \
                    d=json.loads('${line}'); \
                    print('  ${model}:', d.get('status',''))" 2>/dev/null || true
            done
            
            # Re-verify
            curl -sf "http://localhost:${OLLAMA_PORT:-11434}/api/tags" | \
            python3 -c "
import sys, json
data = json.load(sys.stdin)
names = [m['name'] for m in data.get('models', [])]
exit(0 if any('${model}' in n for n in names) else 1)
" 2>/dev/null || {
                log "ERROR" "Model '${model}' still missing after pull — FATAL"
                return 1
            }
            log "SUCCESS" "Model '${model}' pulled and verified"
        fi
    done
    
    log "SUCCESS" "Infrastructure verification complete"
}

# ============================================================
# STEP 2: Create Qdrant collection for Mem0
# ============================================================
setup_qdrant_collections() {
    set -a; source "${ENV_FILE}"; set +a
    log "INFO" "=== Step 2: Qdrant Collection Setup ==="
    
    local qdrant_url="http://localhost:${QDRANT_PORT:-6333}"
    local collection="${MEM0_COLLECTION:-ai_memory}"
    local vector_size=768
    local distance="Cosine"
    
    local existing_code
    existing_code=$(curl -sf -o /dev/null -w "%{http_code}" \
        "${qdrant_url}/collections/${collection}" 2>/dev/null || echo "000")
    
    if [[ "${existing_code}" == "200" ]]; then
        # Verify vector dimensions match
        local existing_size
        existing_size=$(curl -sf "${qdrant_url}/collections/${collection}" | \
            python3 -c "
import sys, json
d = json.load(sys.stdin)
# Handle both flat and nested vector configs
params = d['result']['config']['params']
if 'vectors' in params:
    v = params['vectors']
    if isinstance(v, dict) and 'size' in v:
        print(v['size'])
    elif isinstance(v, dict):
        # Named vectors
        first = list(v.values())[0]
        print(first.get('size', 0))
else:
    print(0)
" 2>/dev/null || echo "0")
        
        if [[ "${existing_size}" == "${vector_size}" ]]; then
            log "SUCCESS" "Collection '${collection}' exists with correct size=${vector_size}"
            return 0
        else
            log "WARN" "Collection '${collection}' exists but size=${existing_size} (expected ${vector_size}) — recreating"
            curl -sf -X DELETE "${qdrant_url}/collections/${collection}" > /dev/null
        fi
    fi
    
    log "INFO" "Creating collection '${collection}' (size=${vector_size}, distance=${distance})..."
    
    local create_response
    local create_code
    create_response=$(curl -sf -w "\n%{http_code}" \
        -X PUT "${qdrant_url}/collections/${collection}" \
        -H "Content-Type: application/json" \
        -d "{
            \"vectors\": {
                \"size\": ${vector_size},
                \"distance\": \"${distance}\"
            },
            \"optimizers_config\": {
                \"default_segment_number\": 2
            },
            \"replication_factor\": 1
        }" 2>&1)
    
    create_code=$(echo "${create_response}" | tail -1)
    local create_body
    create_body=$(echo "${create_response}" | head -n -1)
    
    if [[ "${create_code}" != "200" ]]; then
        log "ERROR" "Collection creation failed — HTTP ${create_code}"
        log "ERROR" "Response: ${create_body}"
        return 1
    fi
    
    # Verify collection is accessible
    local verify_code
    verify_code=$(curl -sf -o /dev/null -w "%{http_code}" \
        "${qdrant_url}/collections/${collection}" 2>/dev/null || echo "000")
    
    [[ "${verify_code}" != "200" ]] && {
        log "ERROR" "Collection created but not accessible — HTTP ${verify_code}"
        return 1
    }
    
    update_env "MEM0_COLLECTION" "${collection}"
    log "SUCCESS" "Qdrant collection '${collection}' created and verified"
}

# ============================================================
# STEP 3: Configure and operationally verify Bifrost
# ============================================================
configure_and_verify_bifrost() {
    set -a; source "${ENV_FILE}"; set +a
    log "INFO" "=== Step 3: Bifrost Configuration and Verification ==="
    
    local bifrost_url="http://localhost:${BIFROST_PORT}"
    
    # Wait for /healthz
    local elapsed=0
    until curl -sf --max-time 5 "${bifrost_url}/healthz" > /dev/null 2>&1; do
        [[ ${elapsed} -ge 120 ]] && {
            log "ERROR" "Bifrost /healthz timeout after 120s"
            log "ERROR" "=== Container inspect ==="
            docker inspect "${LLM_GATEWAY_CONTAINER}" \
                --format "Status={{.State.Status}} Exit={{.State.ExitCode}} Error={{.State.Error}}" \
                2>/dev/null | while IFS= read -r l; do log "LOG" "${l}"; done
            log "ERROR" "=== Container logs ==="
            docker logs "${LLM_GATEWAY_CONTAINER}" --tail 50 2>&1 | \
                while IFS= read -r l; do log "LOG" "${l}"; done
            log "ERROR" "=== Config file content ==="
            if [[ -f "${CONFIG_DIR}/bifrost/config.yaml" ]]; then
                sed "s/${LLM_MASTER_KEY}/[MASKED]/g" \
                    "${CONFIG_DIR}/bifrost/config.yaml" | \
                    while IFS= read -r l; do log "LOG" "${l}"; done
            else
                log "ERROR" "Config file does not exist: ${CONFIG_DIR}/bifrost/config.yaml"
            fi
            return 1
        }
        sleep 5; elapsed=$((elapsed+5))
        log "INFO" "  Waiting for Bifrost... ${elapsed}/120s"
    done
    log "SUCCESS" "Bifrost /healthz OK (${elapsed}s)"
    
    # This is the test that was always missing
    log "INFO" "Testing Bifrost LLM routing (operational verification)..."
    
    local route_result
    local route_code
    route_result=$(curl -sf -w "\n%{http_code}" \
        -X POST "${bifrost_url}/api/chat" \
        -H "Authorization: Bearer ${LLM_MASTER_KEY}" \
        -H "Content-Type: application/json" \
        --max-time 90 \
        -d '{
            "model": "ollama/llama3.2",
            "messages": [{"role": "user", "content": "Say the word: operational"}],
            "stream": false
        }' 2>&1) || true
    
    route_code=$(echo "${route_result}" | tail -1)
    local route_body
    route_body=$(echo "${route_result}" | head -n -1)
    
    if [[ "${route_code}" == "200" ]]; then
        local content
        content=$(echo "${route_body}" | \
            python3 -c "
import sys, json
d = json.load(sys.stdin)
# Handle both OpenAI and Ollama response formats
msg = d.get('message', d.get('choices', [{}])[0].get('message', {}))
print(msg.get('content', '<no content>'))
" 2>/dev/null || echo "${route_body}")
        log "SUCCESS" "Bifrost routing operational — model response: ${content}"
    else
        log "ERROR" "Bifrost routing FAILED — HTTP ${route_code}"
        log "ERROR" "Response body: ${route_body}"
        log "ERROR" ""
        log "ERROR" "=== DIAGNOSIS ==="
        log "ERROR" "If 'account not found': config secret_key does not match Authorization header"
        log "ERROR" "If 'provider not found': provider name in config does not match model prefix"
        log "ERROR" "If connection refused: Ollama container not reachable from Bifrost container"
        log "ERROR" ""
        log "ERROR" "=== Bifrost logs ==="
        docker logs "${LLM_GATEWAY_CONTAINER}" --tail 30 2>&1 | \
            while IFS= read -r l; do log "LOG" "${l}"; done
        log "ERROR" "=== Config (key masked) ==="
        sed "s/${LLM_MASTER_KEY}/[MASKED]/g" \
            "${CONFIG_DIR}/bifrost/config.yaml" 2>/dev/null | \
            while IFS= read -r l; do log "LOG" "${l}"; done
        return 1
    fi
    
    log "SUCCESS" "Bifrost fully operational"
}

# ============================================================
# STEP 4: Configure and operationally verify Mem0
# ============================================================
configure_and_verify_mem0() {
    set -a; source "${ENV_FILE}"; set +a
    log "INFO" "=== Step 4: Mem0 Configuration and Verification ==="
    
    local mem0_url="http://localhost:${MEM0_PORT}"
    # First boot installs pip packages — allow up to 8 minutes
    local max_wait=480
    
    log "INFO" "Waiting for Mem0 /health (first boot pip install may take ~4 minutes)..."
    
    local elapsed=0
    until curl -sf --max-time 10 "${mem0_url}/health" 2>/dev/null | \
          grep -qi "ok\|healthy\|true\|status.*ok"; do
        [[ ${elapsed} -ge ${max_wait} ]] && {
            log "ERROR" "Mem0 /health timeout after ${max_wait}s"
            docker logs "${MEM0_CONTAINER}" --tail 50 2>&1 | \
                while IFS= read -r l; do log "LOG" "${l}"; done
            return 1
        }
        sleep 10; elapsed=$((elapsed+10))
        if [[ $((elapsed % 60)) -eq 0 ]]; then
            log "INFO" "  Mem0 still initializing... ${elapsed}/${max_wait}s"
        fi
    done
    log "SUCCESS" "Mem0 /health OK (${elapsed}s)"
    
    # Brief pause for full initialization
    sleep 5
    
    # OPERATIONAL TEST 1: Write memory
    local test_ts
    test_ts=$(date +%s)
    local tenant_a="verify_tenant_a_${test_ts}"
    local test_content="platform_verify_${test_ts}"
    
    log "INFO" "Testing Mem0 write..."
    local write_result write_code write_body
    write_result=$(curl -sf -w "\n%{http_code}" \
        -X POST "${mem0_url}/v1/memories" \
        -H "Authorization: Bearer ${MEM0_API_KEY}" \
        -H "Content-Type: application/json" \
        --max-time 60 \
        -d "{
            \"messages\": [{\"role\": \"user\", \"content\": \"${test_content}\"}],
            \"user_id\": \"${tenant_a}\"
        }" 2>&1) || true
    
    write_code=$(echo "${write_result}" | tail -1)
    write_body=$(echo "${write_result}" | head -n -1)
    
    if [[ "${write_code}" != "200" ]]; then
        log "ERROR" "Mem0 write FAILED — HTTP ${write_code}"
        log "ERROR" "Response: ${write_body}"
        log "ERROR" "=== Diagnostics ==="
        
        # Check Qdrant collection
        local qdrant_check
        qdrant_check=$(curl -sf \
            "http://localhost:${QDRANT_PORT:-6333}/collections/${MEM0_COLLECTION:-ai_memory}" \
            2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
r = d.get('result', {})
print('Collection: OK, vectors:', r.get('vectors_count', 0))
" 2>/dev/null || echo "Qdrant collection NOT FOUND")
        log "ERROR" "Qdrant: ${qdrant_check}"
        
        # Check nomic-embed-text
        local embed_check
        embed_check=$(curl -sf \
            "http://localhost:${OLLAMA_PORT:-11434}/api/tags" 2>/dev/null | \
            python3 -c "
import sys, json
names = [m['name'] for m in json.load(sys.stdin).get('models', [])]
print('nomic-embed-text present:', any('nomic' in n for n in names))
" 2>/dev/null || echo "Cannot check Ollama")
        log "ERROR" "Ollama: ${embed_check}"
        
        log "ERROR" "=== Mem0 container logs ==="
        docker logs "${MEM0_CONTAINER}" --tail 30 2>&1 | \
            while IFS= read -r l; do log "LOG" "${l}"; done
        return 1
    fi
    log "SUCCESS" "Mem0 write OK (HTTP ${write_code})"
    
    # Allow vector indexing
    sleep 3
    
    # OPERATIONAL TEST 2: Search — same tenant must find the written memory
    log "INFO" "Testing Mem0 search (same tenant)..."
    local search_result search_body
    search_result=$(curl -sf \
        -X POST "${mem0_url}/v1/memories/search" \
        -H "Authorization: Bearer ${MEM0_API_KEY}" \
        -H "Content-Type: application/json" \
        --max-time 30 \
        -d "{\"query\": \"${test_content}\", \"user_id\": \"${tenant_a}\"}" \
        2>/dev/null || echo '{"results":[]}')
    
    local result_count
    result_count=$(echo "${search_result}" | \
        python3 -c "
import sys, json
d = json.load(sys.stdin)
results = d.get('results', d.get('memories', []))
print(len(results))
" 2>/dev/null || echo "0")
    
    if [[ "${result_count}" -gt 0 ]]; then
        log "SUCCESS" "Mem0 search found ${result_count} result(s) — write/search pipeline working"
    else
        log "ERROR" "Mem0 search returned 0 results — embedding or indexing broken"
        log "ERROR" "Search response: ${search_result}"
        return 1
    fi
    
    # OPERATIONAL TEST 3: Tenant isolation — different tenant must see NOTHING
    log "INFO" "Testing Mem0 tenant isolation..."
    local tenant_b="verify_tenant_b_${test_ts}"
    local isolation_result
    isolation_result=$(curl -sf \
        -X POST "${mem0_url}/v1/memories/search" \
        -H "Authorization: Bearer ${MEM0_API_KEY}" \
        -H "Content-Type: application/json" \
        --max-time 30 \
        -d "{\"query\": \"${test_content}\", \"user_id\": \"${tenant_b}\"}" \
        2>/dev/null || echo '{"results":[{"isolation_failed":true}]}')
    
    local isolation_count
    isolation_count=$(echo "${isolation_result}" | \
        python3 -c "
import sys, json
d = json.load(sys.stdin)
results = d.get('results', d.get('memories', []))
print(len(results))
" 2>/dev/null || echo "1")
    
    if [[ "${isolation_count}" -eq 0 ]]; then
        log "SUCCESS" "Tenant isolation verified — tenant_b sees 0 results from tenant_a"
    else
        log "ERROR" "CRITICAL: Tenant isolation BROKEN — tenant_b sees ${isolation_count} result(s)"
        log "ERROR" "Response: ${isolation_result}"
        return 1
    fi
    
    update_env "MEM0_STATUS" "operational"
    log "SUCCESS" "Mem0 fully operational"
}

# ============================================================
# STEP 5: Configure Prometheus with correct container targets
# ============================================================
configure_prometheus() {
    set -a; source "${ENV_FILE}"; set +a
    log "INFO" "=== Step 5: Prometheus Configuration ==="
    
    local prom_config_dir="${CONFIG_DIR}/prometheus"
    mkdir -p "${prom_config_dir}"
    
    # Write prometheus.yml with container-name targets
    # KEY: targets must use container names, not localhost
    # From inside Prometheus container, other services are on Docker network
    # localhost:PORT would target the Prometheus container itself
    cat > "${prom_config_dir}/prometheus.yml" << PROMEOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

  external_labels:
    project: '${PROJECT_NAME}'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'postgres-exporter'
    static_configs:
      - targets: ['${PROJECT_NAME}-postgres-exporter:9187']

  - job_name: 'redis'
    static_configs:
      - targets: ['${REDIS_CONTAINER}:6379']

  - job_name: 'ollama'
    static_configs:
      - targets: ['${OLLAMA_CONTAINER}:${OLLAMA_PORT:-11434}']

  - job_name: 'qdrant'
    static_configs:
      - targets: ['${QDRANT_CONTAINER}:6333']
    metrics_path: /metrics

  - job_name: 'caddy'
    static_configs:
      - targets: ['${CADDY_CONTAINER}:2019']
    metrics_path: /metrics
PROMEOF
    
    chown "${CURRENT_USER}:${CURRENT_USER}" "${prom_config_dir}/prometheus.yml"
    
    # Wait for Prometheus
    wait_for_url "Prometheus" "http://localhost:${PROMETHEUS_PORT:-9090}/-/healthy" 60 || {
        log "WARN" "Prometheus not responding — skipping config reload"
        return 0
    }
    
    # Reload config (requires --web.enable-lifecycle in container command)
    if curl -sf -X POST \
       "http://localhost:${PROMETHEUS_PORT:-9090}/-/reload" > /dev/null 2>&1; then
        log "SUCCESS" "Prometheus config reloaded"
    else
        log "WARN" "Prometheus reload failed — restart container to apply config"
        docker restart "${PROMETHEUS_CONTAINER:-${PROJECT_NAME}-prometheus}" 2>/dev/null || true
        sleep 10
    fi
    
    log "SUCCESS" "Prometheus configured with container-name targets"
}

# ============================================================
# STEP 6: Configure n8n
# ============================================================
configure_n8n() {
    set -a; source "${ENV_FILE}"; set +a
    log "INFO" "=== Step 6: n8n Configuration ==="
    
    local n8n_url="http://localhost:${N8N_PORT:-5678}"
    wait_for_url "n8n" "${n8n_url}/healthz" 180 "ok" || return 1
    
    # Verify the encryption key in the running container matches .env
    local container_key
    container_key=$(docker exec "${N8N_CONTAINER:-${PROJECT_NAME}-n8n}" \
        env 2>/dev/null | grep "^N8N_ENCRYPTION_KEY=" | cut -d= -f2- || echo "")
    
    if [[ -z "${container_key}" ]]; then
        log "ERROR" "N8N_ENCRYPTION_KEY not set in running n8n container"
        log "ERROR" "Check script 2 n8n environment block"
        return 1
    fi
    
    if [[ "${container_key}" != "${N8N_ENCRYPTION_KEY}" ]]; then
        log "ERROR" "N8N_ENCRYPTION_KEY mismatch:"
        log "ERROR" "  Container: ${container_key:0:8}..."
        log "ERROR" "  ENV file:  ${N8N_ENCRYPTION_KEY:0:8}..."
        log "ERROR" "Credentials will be corrupted. Fix script 2 and redeploy."
        return 1
    fi
    log "SUCCESS" "n8n encryption key consistent (${N8N_ENCRYPTION_KEY:0:8}...)"
    
    log "SUCCESS" "n8n configured and operational"
}

# ============================================================
# STEP 7: Configure Flowise
# ============================================================
configure_flowise() {
    set -a; source "${ENV_FILE}"; set +a
    log "INFO" "=== Step 7: Flowise Configuration ==="
    
    local flowise_url="http://localhost:${FLOWISE_PORT:-3001}"
    wait_for_url "Flowise" "${flowise_url}/api/v1/ping" 180 "pong" || return 1
    
    # Verify authenticated API works
    local auth_code
    auth_code=$(curl -sf -o /dev/null -w "%{http_code}" \
        -u "${FLOWISE_USERNAME}:${FLOWISE_PASSWORD}" \
        "${flowise_url}/api/v1/chatflows" 2>/dev/null || echo "000")
    
    if [[ "${auth_code}" == "200" ]]; then
        log "SUCCESS" "Flowise authenticated API operational (HTTP ${auth_code})"
    else
        log "ERROR" "Flowise authenticated API FAILED — HTTP ${auth_code}"
        log "ERROR" "=== Container env (FLOWISE vars) ==="
        docker exec "${FLOWISE_CONTAINER:-${PROJECT_NAME}-flowise}" env 2>/dev/null | \
            grep -i "flowise\|database" | grep -v "PASSWORD" | \
            while IFS= read -r l; do log "LOG" "  ${l}"; done
        log "ERROR" "Check FLOWISE_PASSWORD is in script 2 environment block"
        return 1
    fi
    
    log "SUCCESS" "Flowise configured and operational"
}

# ============================================================
# FINAL: Operational summary — exits non-zero if anything failed
# ============================================================
print_operational_summary() {
    set -a; source "${ENV_FILE}"; set +a
    log "INFO" "=== Final Operational Summary ==="
    
    local pass=0
    local fail=0
    local results=()
    
    check_op() {
        local name="$1"
        local cmd="$2"
        if eval "${cmd}" > /dev/null 2>&1; then
            results+=("✅ ${name}")
            pass=$((pass+1))
        else
            results+=("❌ ${name}")
            fail=$((fail+1))
        fi
    }
    
    # Infrastructure
    check_op "PostgreSQL" \
        "docker exec ${POSTGRES_CONTAINER} pg_isready -U ${POSTGRES_USER} -q"
    check_op "Redis" \
        "docker exec ${REDIS_CONTAINER} redis-cli ping | grep -q PONG"
    check_op "Qdrant" \
        "curl -sf http://localhost:${QDRANT_PORT:-6333}/healthz"
    check_op "Ollama llama3.2" \
        "curl -sf http://localhost:${OLLAMA_PORT:-11434}/api/tags | grep -q llama3.2"
    check_op "Ollama nomic-embed-text" \
        "curl -sf http://localhost:${OLLAMA_PORT:-11434}/api/tags | grep -q nomic-embed-text"
    
    # Bifrost — both healthcheck AND routing
    check_op "Bifrost /healthz" \
        "curl -sf http://localhost:${BIFROST_PORT}/healthz"
    check_op "Bifrost routing (llm call)" \
        "curl -sf -X POST http://localhost:${BIFROST_PORT}/api/chat \
         -H 'Authorization: Bearer ${LLM_MASTER_KEY}' \
         -H 'Content-Type: application/json' --max-time 60 \
         -d '{\"model\":\"ollama/llama3.2\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"stream\":false}' \
         | grep -q 'content\|message'"
    
    # Mem0 — both health AND write
    check_op "Mem0 /health" \
        "curl -sf http://localhost:${MEM0_PORT}/health | grep -qi ok"
    check_op "Mem0 write operation" \
        "curl -sf -X POST http://localhost:${MEM0_PORT}/v1/memories \
         -H 'Authorization: Bearer ${MEM0_API_KEY}' \
         -H 'Content-Type: application/json' --max-time 30 \
         -d '{\"messages\":[{\"role\":\"user\",\"content\":\"final_check\"}],\"user_id\":\"final_verify\"}' \
         | grep -q 'id\|result'"
    
    # Application services
    check_op "n8n /healthz" \
        "curl -sf http://localhost:${N8N_PORT}/healthz | grep -q ok"
    check_op "Flowise /api/v1/ping" \
        "curl -sf http://localhost:${FLOWISE_PORT}/api/v1/ping | grep -q pong"
    check_op "Flowise authenticated" \
        "curl -sf -u ${FLOWISE_USERNAME}:${FLOWISE_PASSWORD} \
         http://localhost:${FLOWISE_PORT}/api/v1/chatflows | python3 -c 'import sys,json; json.load(sys.stdin); exit(0)'"
    check_op "OpenWebUI" \
        "curl -sf http://localhost:${OPENWEBUI_PORT}/ | grep -qi 'html\|open.webui'"
    check_op "AnythingLLM" \
        "curl -sf http://localhost:${ANYTHINGLLM_PORT}/api/ping | grep -qi 'ok\|pong'"
    check_op "Prometheus /-/healthy" \
        "curl -sf http://localhost:${PROMETHEUS_PORT:-9090}/-/healthy"
    check_op "Caddy metrics" \
        "curl -sf http://localhost:2019/metrics | grep -q caddy"
    
    echo ""
    log "INFO" "══════════════════════════════════════════"
    for r in "${results[@]}"; do
        log "INFO" "  ${r}"
    done
    log "INFO" "══════════════════════════════════════════"
    log "INFO" "Results: ${pass} passed, ${fail} failed"
    
    if [[ ${fail} -eq 0 ]]; then
        log "SUCCESS" ""
        log "SUCCESS" "🎉 PLATFORM 100% OPERATIONAL"
        log "SUCCESS" ""
        log "INFO" "Access URLs:"
        log "INFO" "  Dashboard:   https://${DOMAIN}"
        log "INFO" "  OpenWebUI:   https://chat.${DOMAIN}"
        log "INFO" "  n8n:         https://n8n.${DOMAIN}"
        log "INFO" "  Flowise:     https://flowise.${DOMAIN}"
        log "INFO" "  AnythingLLM: https://anythingllm.${DOMAIN}"
        log "INFO" "  Prometheus:  https://prometheus.${DOMAIN}"
        log "INFO" ""
        log "INFO" "Bifrost endpoint: http://localhost:${BIFROST_PORT}/api/chat"
        log "INFO" "Mem0 endpoint:    http://localhost:${MEM0_PORT}/v1/memories"
        update_env "PLATFORM_STATUS" "operational"
        update_env "PLATFORM_READY_AT" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    else
        log "ERROR" ""
        log "ERROR" "❌ ${fail} check(s) FAILED — platform NOT operational"
        log "ERROR" "Check ${LOG_FILE} for detailed diagnostics"
        return 1
    fi
}

main() {
    set -a; source "${ENV_FILE}"; set +a
    log "INFO" "Platform configuration starting — $(date)"
    log "INFO" "Project: ${PROJECT_NAME} | Domain: ${DOMAIN}"
    
    verify_infrastructure         || { log "ERROR" "ABORT: Infrastructure"; exit 1; }
    setup_qdrant_collections      || { log "ERROR" "ABORT: Qdrant collections"; exit 1; }
    configure_and_verify_bifrost  || { log "ERROR" "ABORT: Bifrost"; exit 1; }
    configure_and_verify_mem0     || { log "ERROR" "ABORT: Mem0"; exit 1; }
    configure_n8n                 || { log "ERROR" "ABORT: n8n"; exit 1; }
    configure_flowise             || { log "ERROR" "ABORT: Flowise"; exit 1; }
    configure_prometheus          || { log "ERROR" "ABORT: Prometheus"; exit 1; }
    configure_caddy               || { log "ERROR" "ABORT: Caddy"; exit 1; }
    print_operational_summary     || exit 1
}

main "$@"
