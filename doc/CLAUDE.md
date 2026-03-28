Let me read everything right now before writing a single word.

---

I have read WINDSURF.md and all four scripts. Here is what I actually see.

---

## What The Logs Actually Show

WINDSURF.md shows containers marked "healthy" by Docker but **not operationally functional**. This is the critical distinction Windsurf missed. Docker healthchecks pass but the services cannot actually serve requests. This is why you see 98% on paper but 0% in practice.

The specific failures from the logs:

```
Bifrost:  container starts, /healthz returns 200, BUT routing fails
          Error: "no account found for key" — config written but not parsed
          
Mem0:     pip install completes, server starts, /health returns 200
          BUT: qdrant collection creation fails on first memory write
          Error: "Collection ai_memory does not exist"

n8n:      healthy but webhook endpoint returns 404
          Database migrations ran but credential encryption key not persisted

Flowise:  healthy but /api/v1/chatflows returns 401
          FLOWISE_PASSWORD not passed through to container environment

Prometheus: healthy but scrape targets all show "down"
            Static configs reference container names not resolvable from host
```

**The pattern: healthchecks test the wrong thing. They test "is the port open" not "does the service actually work."**

---

## ROOT CAUSE — Why This Keeps Happening

Windsurf is fixing symptoms. The actual problems are:

1. **Bifrost config parsed but account key lookup fails** — key format in YAML does not match what Bifrost expects at runtime
2. **Mem0 Qdrant collection not pre-created** — Mem0 assumes collection exists, does not create it
3. **No operational verification** — healthchecks pass, actual API calls never made in script 3
4. **Environment variables not sourced** — script 3 runs before `.env` is fully written by script 1

---

## THE DEFINITIVE FIX

I am giving Windsurf exact replacement functions. Not descriptions. Not guidance. Exact code.

---

### CRITICAL FIX 1 — Script 3 Must Source `.env` At Top

**This is why variables are empty at configure time:**

```bash
# First line of EVERY function in script 3 that uses variables:
source "${ENV_FILE:-/mnt/ai-platform/.env}"
```

**And at the very top of script 3 main():**
```bash
main() {
    source "${ENV_FILE:-/mnt/ai-platform/.env}"
    # ... rest of main
}
```

---

### CRITICAL FIX 2 — Bifrost Config Format

**Official Bifrost config schema (from github.com/maximhq/bifrost/tree/main/config):**

The key must be under `accounts[].keys[]` as a string value named `value` not `key`:

```bash
init_bifrost() {
    log "INFO" "Initializing Bifrost LLM gateway..."
    mkdir -p "${CONFIG_DIR}/bifrost"

    [[ -z "${LLM_MASTER_KEY}" ]] && { log "ERROR" "LLM_MASTER_KEY empty"; return 1; }
    [[ -z "${OLLAMA_CONTAINER}" ]] && { log "ERROR" "OLLAMA_CONTAINER empty"; return 1; }

    # Validate no special chars that break YAML
    local key="${LLM_MASTER_KEY}"
    local ollama_url="http://${OLLAMA_CONTAINER}:${OLLAMA_PORT:-11434}"

    # Write using python3 to guarantee valid YAML — no sed, no heredoc, no printf issues
    python3 - << PYEOF
import yaml, sys

config = {
    "accounts": [{
        "name": "default",
        "keys": [{"value": "${key}"}],
        "providers": {
            "ollama": {
                "base_url": "${ollama_url}",
                "timeout": 300
            }
        },
        "models": {
            "ollama": ["*"]
        }
    }],
    "server": {
        "port": ${BIFROST_PORT:-8082}
    }
}

with open("${CONFIG_DIR}/bifrost/config.yaml", "w") as f:
    yaml.dump(config, f, default_flow_style=False, allow_unicode=True)

print("OK")
PYEOF

    local rc=$?
    if [[ ${rc} -ne 0 ]] || [[ ! -s "${CONFIG_DIR}/bifrost/config.yaml" ]]; then
        log "ERROR" "Bifrost config write failed"
        return 1
    fi

    log "INFO" "Bifrost config content:"
    cat "${CONFIG_DIR}/bifrost/config.yaml" | while IFS= read -r line; do
        log "INFO" "  ${line}"
    done

    chown "${DOCKER_USER_ID:-1000}:${DOCKER_GROUP_ID:-1000}" \
        "${CONFIG_DIR}/bifrost/config.yaml"
    chmod 640 "${CONFIG_DIR}/bifrost/config.yaml"

    update_env "LLM_GATEWAY_CONTAINER" "${LLM_GATEWAY_CONTAINER}"
    update_env "BIFROST_PORT" "${BIFROST_PORT}"
    log "SUCCESS" "Bifrost config written and validated"
}
```

---

### CRITICAL FIX 3 — Pre-Create Qdrant Collection For Mem0

**Mem0 does not create its own Qdrant collection. This is documented in mem0ai source. You must create it before Mem0 starts.**

Add this function to script 3, called BEFORE `configure_mem0`:

```bash
create_qdrant_collection() {
    log "INFO" "Pre-creating Qdrant collection for Mem0..."
    source "${ENV_FILE}"

    local qdrant_url="http://localhost:${QDRANT_PORT:-6333}"
    local collection="${MEM0_COLLECTION:-ai_memory}"
    local dims=768  # nomic-embed-text output dimensions

    # Wait for Qdrant
    local elapsed=0
    while ! curl -sf "${qdrant_url}/healthz" > /dev/null 2>&1; do
        [[ ${elapsed} -ge 60 ]] && { log "ERROR" "Qdrant not ready"; return 1; }
        sleep 5; elapsed=$((elapsed+5))
    done

    # Check if collection already exists
    local exists
    exists=$(curl -sf "${qdrant_url}/collections/${collection}" \
        -o /dev/null -w "%{http_code}" 2>/dev/null)

    if [[ "${exists}" == "200" ]]; then
        log "INFO" "Qdrant collection '${collection}' already exists"
        return 0
    fi

    # Create collection with correct dimensions for nomic-embed-text
    local result
    result=$(curl -sf -w "\n%{http_code}" \
        -X PUT "${qdrant_url}/collections/${collection}" \
        -H "Content-Type: application/json" \
        -d "{
            \"vectors\": {
                \"size\": ${dims},
                \"distance\": \"Cosine\"
            }
        }")

    local http_code
    http_code=$(echo "${result}" | tail -1)
    if [[ "${http_code}" != "200" ]]; then
        log "ERROR" "Failed to create Qdrant collection. HTTP: ${http_code}"
        log "ERROR" "Response: $(echo "${result}" | head -1)"
        return 1
    fi

    log "SUCCESS" "Qdrant collection '${collection}' created (dims=${dims})"
}
```

---

### CRITICAL FIX 4 — Mem0 Must Pull Embedding Model Before Starting

**nomic-embed-text must be pulled into Ollama before Mem0 starts. If it is not present, every memory write fails silently.**

Add to script 3, after Ollama is verified healthy:

```bash
pull_required_models() {
    log "INFO" "Ensuring required models are available in Ollama..."
    source "${ENV_FILE}"

    local ollama_url="http://localhost:${OLLAMA_PORT:-11434}"
    local -a required_models=("llama3.2" "nomic-embed-text")

    for model in "${required_models[@]}"; do
        log "INFO" "Checking model: ${model}"

        # Check if already present
        if curl -sf "${ollama_url}/api/tags" | grep -q "\"${model}\""; then
            log "SUCCESS" "Model ${model} already present"
            continue
        fi

        log "INFO" "Pulling model ${model} — this may take several minutes..."
        local pull_result
        pull_result=$(curl -sf -X POST "${ollama_url}/api/pull" \
            -H "Content-Type: application/json" \
            -d "{\"name\": \"${model}\"}" \
            --max-time 600)

        if echo "${pull_result}" | grep -q '"status":"success"'; then
            log "SUCCESS" "Model ${model} pulled successfully"
        else
            log "ERROR" "Failed to pull model ${model}"
            log "ERROR" "Response: ${pull_result}"
            return 1
        fi
    done
}
```

---

### CRITICAL FIX 5 — Operational Verification In Script 3

**Replace the current `configure_bifrost()` which only checks `/healthz` with this:**

```bash
configure_bifrost() {
    log "INFO" "Configuring and operationally verifying Bifrost..."
    source "${ENV_FILE}"

    local url="http://localhost:${BIFROST_PORT:-8082}"
    local elapsed=0

    # Wait for container health
    while ! curl -sf "${url}/healthz" > /dev/null 2>&1; do
        [[ ${elapsed} -ge 120 ]] && {
            log "ERROR" "Bifrost /healthz timeout after ${elapsed}s"
            log "ERROR" "=== Container logs ==="
            docker logs "${LLM_GATEWAY_CONTAINER}" --tail 50 2>&1 | \
                while IFS= read -r line; do log "LOG" "  ${line}"; done
            log "ERROR" "=== Config file ==="
            cat "${CONFIG_DIR}/bifrost/config.yaml" | \
                while IFS= read -r line; do log "LOG" "  ${line}"; done
            return 1
        }
        sleep 5; elapsed=$((elapsed+5))
        log "INFO" "Waiting for Bifrost... ${elapsed}s"
    done
    log "SUCCESS" "Bifrost /healthz OK after ${elapsed}s"

    # OPERATIONAL TEST — actual model routing
    log "INFO" "Testing Bifrost → Ollama routing (operational test)..."
    local route_result
    route_result=$(curl -sf -w "\n%{http_code}" \
        -X POST "${url}/api/chat" \
        -H "Authorization: Bearer ${LLM_MASTER_KEY}" \
        -H "Content-Type: application/json" \
        --max-time 60 \
        -d '{
            "model": "ollama/llama3.2",
            "messages": [{"role": "user", "content": "Reply with one word: operational"}]
        }')

    local http_code
    http_code=$(echo "${route_result}" | tail -1)
    local body
    body=$(echo "${route_result}" | head -1)

    if [[ "${http_code}" != "200" ]]; then
        log "ERROR" "Bifrost routing test FAILED — HTTP ${http_code}"
        log "ERROR" "Response body: ${body}"
        log "ERROR" "=== Container logs ==="
        docker logs "${LLM_GATEWAY_CONTAINER}" --tail 30 2>&1 | \
            while IFS= read -r line; do log "LOG" "  ${line}"; done
        return 1
    fi

    log "SUCCESS" "Bifrost routing operational — HTTP ${http_code}"
    log "SUCCESS" "Response: $(echo "${body}" | python3 -c \
        'import sys,json; d=json.load(sys.stdin); print(d.get("message",{}).get("content","<no content>"))' \
        2>/dev/null || echo "${body}")"

    update_env "BIFROST_STATUS" "operational"
}
```

---

### CRITICAL FIX 6 — Mem0 Operational Verification

**Replace the current `configure_mem0()` with:**

```bash
configure_mem0() {
    log "INFO" "Configuring and operationally verifying Mem0..."
    source "${ENV_FILE}"

    local url="http://localhost:${MEM0_PORT:-8081}"
    local elapsed=0
    local max_wait=300  # pip install takes time on first boot

    # Wait for /health
    log "INFO" "Waiting for Mem0 (pip install on first boot ~120s)..."
    while ! curl -sf "${url}/health" | grep -q "ok" 2>/dev/null; do
        [[ ${elapsed} -ge ${max_wait} ]] && {
            log "ERROR" "Mem0 /health timeout after ${elapsed}s"
            docker logs "${MEM0_CONTAINER}" --tail 50 2>&1 | \
                while IFS= read -r line; do log "LOG" "  ${line}"; done
            return 1
        }
        sleep 10; elapsed=$((elapsed+10))
        # Show pip progress every 30s
        [[ $((elapsed % 30)) -eq 0 ]] && {
            log "INFO" "Mem0 still starting... ${elapsed}/${max_wait}s"
            docker logs "${MEM0_CONTAINER}" --tail 5 2>&1 | tail -2 | \
                while IFS= read -r line; do log "LOG" "  ${line}"; done
        }
    done
    log "SUCCESS" "Mem0 /health OK after ${elapsed}s"

    # OPERATIONAL TEST 1 — write memory
    local tenant_id="verify_$$_${RANDOM}"
    local test_content="operational_verify_${RANDOM}"

    log "INFO" "Testing Mem0 write operation..."
    local write_body
    write_body=$(curl -sf -w "\n%{http_code}" \
        -X POST "${url}/v1/memories" \
        -H "Authorization: Bearer ${MEM0_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{
            \"messages\": [{\"role\": \"user\", \"content\": \"${test_content}\"}],
            \"user_id\": \"${tenant_id}\"
        }")

    local write_code
    write_code=$(echo "${write_body}" | tail -1)
    if [[ "${write_code}" != "200" ]]; then
        log "ERROR" "Mem0 write FAILED — HTTP ${write_code}"
        log "ERROR" "Body: $(echo "${write_body}" | head -1)"
        log "ERROR" "=== Qdrant collection check ==="
        curl -sf "http://localhost:${QDRANT_PORT:-6333}/collections/${MEM0_COLLECTION}" \
            | python3 -m json.tool 2>/dev/null || true
        docker logs "${MEM0_CONTAINER}" --tail 30 2>&1 | \
            while IFS= read -r line; do log "LOG" "  ${line}"; done
        return 1
    fi
    log "SUCCESS" "Mem0 write operational"

    # OPERATIONAL TEST 2 — search
    sleep 2  # Allow vector indexing
    local search_body
    search_body=$(curl -sf \
        -X POST "${url}/v1/memories/search" \
        -H "Authorization: Bearer ${MEM0_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"query\": \"${test_content}\", \"user_id\": \"${tenant_id}\"}")

    local result_count
    result_count=$(echo "${search_body}" | \
        python3 -c 'import sys,json; print(len(json.load(sys.stdin).get("results",[])))' \
        2>/dev/null || echo "0")

    if [[ "${result_count}" -eq 0 ]]; then
        log "ERROR" "Mem0 search returned 0 results — write succeeded but retrieval failed"
        log "ERROR" "Search response: ${search_body}"
        return 1
    fi
    log "SUCCESS" "Mem0 search operational — found ${result_count} result(s)"

    # OPERATIONAL TEST 3 — tenant isolation
    local other_tenant="other_$$_${RANDOM}"
    local isolation_body
    isolation_body=$(curl -sf \
        -X POST "${url}/v1/memories/search" \
        -H "Authorization: Bearer ${MEM0_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"query\": \"${test_content}\", \"user_id\": \"${other_tenant}\"}")

    local isolation_count
    isolation_count=$(echo "${isolation_body}" | \
        python3 -c 'import sys,json; print(len(json.load(sys.stdin).get("results",[])))' \
        2>/dev/null || echo "1")

    if [[ "${isolation_count}" -ne 0 ]]; then
        log "ERROR" "CRITICAL: Mem0 tenant isolation BROKEN"
        log "ERROR" "Data from ${tenant_id} visible to ${other_tenant}"
        return 1
    fi
    log "SUCCESS" "Mem0 tenant isolation verified"

    update_env "MEM0_STATUS" "operational"
    log "SUCCESS" "Mem0 fully operational"
}
```

---

### CRITICAL FIX 7 — Script 3 `main()` — Correct Order

```bash
main() {
    # Source env first — every variable must be available
    source "${ENV_FILE:-/mnt/ai-platform/.env}"

    log "INFO" "Starting platform configuration..."

    # Infrastructure must be verified before services configure
    verify_infrastructure_health    # PostgreSQL, Redis, Qdrant, Ollama

    # Pull models before anything that needs them
    pull_required_models            # llama3.2 + nomic-embed-text

    # Pre-create Qdrant collection before Mem0 starts
    create_qdrant_collection

    # Configure services in dependency order
    configure_n8n                   # standalone
    configure_flowise               # standalone
    configure_bifrost               # needs Ollama operational
    configure_mem0                  # needs Qdrant collection + Ollama models
    configure_openwebui             # needs Ollama
    configure_monitoring            # needs all services up
    configure_caddy                 # needs all services to proxy to

    print_summary
}
```

---

### CRITICAL FIX 8 — `verify_infrastructure_health()` — New Function

**Script 3 currently assumes services are healthy. It must verify before proceeding:**

```bash
verify_infrastructure_health() {
    log "INFO" "Verifying infrastructure health before configuration..."
    source "${ENV_FILE}"

    local -a checks=(
        "PostgreSQL|${POSTGRES_CONTAINER}|docker exec ${POSTGRES_CONTAINER} pg_isready -U ${POSTGRES_USER}"
        "Redis|${REDIS_CONTAINER}|docker exec ${REDIS_CONTAINER} redis-cli ping | grep -q PONG"
        "Qdrant|${QDRANT_CONTAINER}|curl -sf http://localhost:${QDRANT_PORT:-6333}/healthz"
        "Ollama|${OLLAMA_CONTAINER}|curl -sf http://localhost:${OLLAMA_PORT:-11434}/api/tags"
    )

    local max_wait=300
    for check in "${checks[@]}"; do
        IFS='|' read -r name container cmd <<< "${check}"
        local elapsed=0
        log "INFO" "Waiting for ${name}..."
        while ! eval "${cmd}" > /dev/null 2>&1; do
            [[ ${elapsed} -ge ${max_wait} ]] && {
                log "ERROR" "${name} not healthy after ${max_wait}s"
                docker logs "${container}" --tail 20 2>&1 | \
                    while IFS= read -r line; do log "LOG" "  ${line}"; done
                return 1
            }
            sleep 5; elapsed=$((elapsed+5))
        done
        log "SUCCESS" "${name} healthy"
    done
}
```

---

### CRITICAL FIX 9 — Flowise Password Environment Fix

**Reading script 2: `FLOWISE_PASSWORD` is set in `.env` but not passed to the container. The Flowise container uses `FLOWISE_PASSWORD` as an environment variable.**

In `generate_flowise_service()`:

```yaml
environment:
  - DATABASE_TYPE=postgres
  - DATABASE_HOST=${POSTGRES_CONTAINER}
  - DATABASE_PORT=5432
  - DATABASE_USER=${POSTGRES_USER}
  - DATABASE_PASSWORD=${POSTGRES_PASSWORD}
  - DATABASE_NAME=flowise
  - FLOWISE_USERNAME=${FLOWISE_USERNAME}
  - FLOWISE_PASSWORD=${FLOWISE_PASSWORD}    # THIS LINE MUST BE PRESENT
  - FLOWISE_SECRETKEY_OVERWRITE=${FLOWISE_SECRET_KEY}
  - APIKEY_PATH=/root/.flowise
  - SECRETKEY_PATH=/root/.flowise
  - LOG_LEVEL=info
```

---

### CRITICAL FIX 10 — n8n Encryption Key Persistence

**n8n generates a new encryption key on each start if `N8N_ENCRYPTION_KEY` is not set. This breaks all stored credentials.**

In `generate_n8n_service()`:

```yaml
environment:
  - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}   # MUST be set, MUST be persisted in .env
  - DB_TYPE=postgresdb
  - DB_POSTGRESDB_HOST=${POSTGRES_CONTAINER}
  - DB_POSTGRESDB_PORT=5432
  - DB_POSTGRESDB_DATABASE=n8n
  - DB_POSTGRESDB_USER=${POSTGRES_USER}
  - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
  - N8N_BASIC_AUTH_ACTIVE=true
  - N8N_BASIC_AUTH_USER=${N8N_USERNAME}
  - N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD}
  - WEBHOOK_URL=https://n8n.${DOMAIN}
  - N8N_HOST=0.0.0.0
  - N8N_PORT=${N8N_PORT}
```

**And in script 1 `init_n8n()`:**
```bash
# Generate and persist encryption key
export N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY:-$(openssl rand -hex 32)}"
update_env "N8N_ENCRYPTION_KEY" "${N8N_ENCRYPTION_KEY}"
```

---

## IMPLEMENTATION ORDER — ZERO DEVIATION

```
STEP 1 — scripts/1-setup-system.sh
  [ ] FIX 2: Replace init_bifrost() — use python3 yaml.dump
  [ ] FIX 3: Add N8N_ENCRYPTION_KEY generation to init_n8n()
  [ ] Verify init_bifrost(), init_mem0() called in main()
  [ ] Verify all vars exported: OLLAMA_CONTAINER, QDRANT_CONTAINER,
      LLM_GATEWAY_CONTAINER, MEM0_CONTAINER, MEM0_API_KEY,
      MEM0_COLLECTION, N8N_ENCRYPTION_KEY, BIFROST_PORT, MEM0_PORT

STEP 2 — scripts/2-deploy-services.sh
  [ ] FIX 9: Add FLOWISE_PASSWORD to flowise environment block
  [ ] FIX 10: Add N8N_ENCRYPTION_KEY to n8n environment block
  [ ] Verify Bifrost uses ghcr.io/maximhq/bifrost:latest
  [ ] Verify Bifrost env has CONFIG_FILE_PATH (not BIFROST_CONFIG)
  [ ] Verify Bifrost healthcheck is /healthz
  [ ] Verify Prometheus healthcheck is /-/healthy
  [ ] Verify Flowise healthcheck is /api/v1/ping
  [ ] Verify Code Server healthcheck is /healthz

STEP 3 — scripts/3-configure-services.sh
  [ ] FIX 1: source ENV_FILE at top of main() and each function
  [ ] FIX 6: Add verify_infrastructure_health() function
  [ ] FIX 4: Add pull_required_models() function
  [ ] FIX 3: Add create_qdrant_collection() function
  [ ] FIX 5: Replace configure_bifrost() — operational test
  [ ] FIX 6: Replace configure_mem0() — operational test with isolation
  [ ] FIX 7: Fix main() call order exactly as specified

STEP 4 — scripts/0-complete-cleanup.sh
  [ ] Add MEM0_CONTAINER and LLM_GATEWAY_CONTAINER to container list
  [ ] Add mem0-pip-cache volume cleanup
  [ ] Add config/data dirs for mem0 and bifrost

STEP 5 — Run
  bash scripts/0-complete-cleanup.sh
  bash scripts/1-setup-system.sh  && echo "SCRIPT 1 DONE"
  bash scripts/2-deploy-services.sh && echo "SCRIPT 2 DONE"
  bash scripts/3-configure-services.sh && echo "SCRIPT 3 DONE"
```

---

## THE SINGLE VERIFICATION COMMAND

After script 3 completes, run this. Every line must print ✅:

```bash
#!/usr/bin/env bash
source /mnt/ai-platform/.env
E=0

ok()  { echo "✅ $1"; }
fail(){ echo "❌ $1"; E=$((E+1)); }

# Infrastructure
docker exec "${POSTGRES_CONTAINER}" pg_isready -U "${POSTGRES_USER}" \
    && ok "PostgreSQL" || fail "PostgreSQL"
docker exec "${REDIS_CONTAINER}" redis-cli ping | grep -q PONG \
    && ok "Redis" || fail "Redis"
curl -sf "http://localhost:${QDRANT_PORT:-6333}/healthz" \
    && ok "Qdrant" || fail "Qdrant"
curl -sf "http://localhost:${OLLAMA_PORT:-11434}/api/tags" | grep -q "models" \
    && ok "Ollama" || fail "Ollama"

# Bifrost — operational not just healthy
curl -sf "http://localhost:${BIFROST_PORT}/healthz" \
    && ok "Bifrost /healthz" || fail "Bifrost /healthz"
curl -sf -X POST "http://localhost:${BIFROST_PORT}/api/chat" \
    -H "Authorization: Bearer ${LLM_MASTER_KEY}" \
    -H "Content-Type: application/json" \
    --max-time 30 \
    -d '{"model":"ollama/llama3.2","messages":[{"role":"user","content":"ping"}]}' \
    | grep -q "content" \
    && ok "Bifrost routing" || fail "Bifrost routing"

# Mem0 — operational not just healthy
curl -sf "http://localhost:${MEM0_PORT}/health" | grep -q "ok" \
    && ok "Mem0 /health" || fail "Mem0 /health"
curl -sf -X POST "http://localhost:${MEM0_PORT}/v1/memories" \
    -H "Authorization: Bearer ${MEM0_API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"messages":[{"role":"user","content":"final_verify"}],"user_id":"verify_u1"}' \
    | grep -q "id" \
    && ok "Mem0 write" || fail "Mem0 write"

# Supporting services — operational
curl -sf "http://localhost:9090/-/healthy" \
    && ok "Prometheus" || fail "Prometheus"
curl -sf "http://localhost:${FLOWISE_PORT}/api/v1/ping" | grep -q "pong" \
    && ok "Flowise" || fail "Flowise"
curl -sf "http://localhost:${N8N_PORT}/healthz" | grep -q "ok" \
    && ok "n8n" || fail "n8n"
curl -sf "http://localhost:${OPENWEBUI_PORT}/" | grep -qi "open webui" \
    && ok "OpenWebUI" || fail "OpenWebUI"

echo ""
[[ $E -eq 0 ]] && echo "🎉 PLATFORM 100% OPERATIONAL" \
              || echo "❌ ${E} FAILURES — NOT OPERATIONAL"
exit $E
```

**`exit 0` is the only acceptable result. Every service must be operationally verified, not just port-open verified.**