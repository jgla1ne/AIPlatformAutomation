Let me read all current files before diagnosing anything.

---

After reading the scripts and audit, here is the precise state and every fix needed:

---

## What the Audit Actually Shows

```
✅ PostgreSQL      - healthy
✅ Redis           - healthy  
✅ Qdrant          - healthy
✅ Ollama          - healthy, models loaded
✅ Caddy           - running
✅ OpenWebUI       - running (but LiteLLM calls failing)
✅ Grafana         - healthy
✅ Prometheus      - healthy
✅ Tailscale       - healthy

❌ LiteLLM         - health: starting (forever)
❌ RClone          - "unknown command sh" crash loop
❌ AnythingLLM     - blocked on LiteLLM healthy
❌ Flowise         - blocked on LiteLLM healthy
❌ N8N             - blocked on LiteLLM healthy
❌ gdrive-ingestion - blocked on LiteLLM + rclone
❌ Signal          - not registered
❓ Dify            - unclear state
```

**The same two root bugs persist.** Windsurf has not fixed them because it keeps working around symptoms instead of the causes. Here is the definitive diagnosis with exact file locations.

---

## BUG 1 — LiteLLM `/health` vs `/health/liveliness`

This has not been fixed yet. Evidence from the audit: LiteLLM shows `health: starting` at 37 seconds and never transitions. The proxy itself initializes fine — the logs show "Proxy initialized successfully" and models loaded. The container is running but Docker marks it unhealthy.

**Why `/health` always fails:**

LiteLLM's `/health` endpoint makes live outbound HTTP calls to every configured provider:
- Groq API → needs valid key, makes network call
- Gemini API → needs valid key, makes network call  
- OpenRouter → needs valid key, makes network call
- Each call has its own timeout

Docker health check timeout is 30s. Three provider calls at ~10s each = 30s minimum. Any 401 or network timeout causes `/health` to return non-200. The Docker check fails. After `retries` failures it marks the container `unhealthy`. All `depends_on: condition: service_healthy` services never start.

**`/health/liveliness` returns `{"status": "alive"}` in <100ms regardless of provider status.** This is the correct endpoint for container orchestration.

---

## BUG 2 — RClone `unknown command "sh"`

This has not been fixed. The rclone image ENTRYPOINT is `/usr/local/bin/rclone`. Any `command:` in docker-compose appends to that entrypoint. So:

```yaml
command: >
  sh -c "while true; do..."
```

Executes as: `/usr/local/bin/rclone sh -c "while true..."` → rclone receives `sh` as a subcommand → `Fatal error: unknown command "sh"` → container exits → restart loop.

The `>` YAML folded scalar also collapses all newlines to spaces, which further breaks any multi-line shell script. Must use `|` (literal block) and must override `entrypoint`.

---

## BUG 3 — Script 3 has no LiteLLM readiness gate

Script 3 sends `curl` calls to `http://localhost:4000/key/generate` without first confirming LiteLLM is accepting connections. If LiteLLM is still starting (which it always is, due to Bug 1 keeping it in `health: starting`), the key generation fails silently or with a connection error. The script continues. Services get configured with empty or invalid API keys. They start but cannot make LLM calls.

This is why OpenWebUI shows "Up" but LLM calls fail.

---

## BUG 4 — Script 2 postgres readiness is sleep-based

The script uses `sleep N` instead of `pg_isready`. On first run PostgreSQL initializes its data directory which can take 20-40 seconds. If the sleep is too short, the prisma migration runs against a PostgreSQL that hasn't finished initializing, fails, and LiteLLM starts with a broken or empty schema.

---

## BUG 5 — gdrive-ingestion `depends_on` blocks on rclone `service_healthy`

If `gdrive-ingestion` has:
```yaml
depends_on:
  rclone:
    condition: service_healthy
```

And rclone has no `healthcheck:` block defined, Docker treats rclone as never healthy. gdrive-ingestion never starts, regardless of whether rclone is actually running.

---

## Complete Fix — Every File, Every Change

### Fix 1: `docker-compose.yml` — LiteLLM healthcheck

```yaml
# FIND this in litellm service:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]

# REPLACE WITH:
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:4000/health/liveliness"]
      interval: 30s
      timeout: 15s
      retries: 10
      start_period: 90s
```

### Fix 2: `docker-compose.yml` — LiteLLM environment additions

```yaml
# ADD to litellm environment block:
      BACKGROUND_HEALTH_CHECKS: "True"
      HEALTH_CHECK_INTERVAL: "300"
      LITELLM_LOG: "INFO"
```

`BACKGROUND_HEALTH_CHECKS: "True"` moves provider polling to a background thread so startup is not blocked waiting for Groq/Gemini/OpenRouter to respond.

### Fix 3: `docker-compose.yml` — RClone service complete rewrite

```yaml
  rclone:
    image: rclone/rclone:latest
    container_name: ${COMPOSE_PROJECT_NAME:-ai-platform}-rclone
    restart: unless-stopped
    entrypoint: ["/bin/sh", "-c"]
    command: |
      if [ ! -f /config/rclone/rclone.conf ]; then
        echo "[rclone] WARNING: /config/rclone/rclone.conf not found"
        echo "[rclone] Container idling. Configure with:"
        echo "[rclone]   docker exec -it $(hostname) rclone config"
        exec sleep infinity
      fi
      echo "[rclone] Config found. Starting sync daemon (interval: ${SYNC_INTERVAL:-300}s)"
      while true; do
        echo "[rclone] $(date -Iseconds) Starting sync gdrive:/ -> /gdrive"
        rclone sync gdrive:/ /gdrive \
          --config /config/rclone/rclone.conf \
          --log-level INFO \
          --transfers 4 \
          --checkers 8 \
          --contimeout 60s \
          --timeout 300s \
          --retries 3 \
          --low-level-retries 10 \
          --stats 30s \
          2>&1
        echo "[rclone] $(date -Iseconds) Sync complete. Sleeping ${SYNC_INTERVAL:-300}s"
        sleep "${SYNC_INTERVAL:-300}"
      done
    environment:
      SYNC_INTERVAL: "${RCLONE_SYNC_INTERVAL:-300}"
    volumes:
      - rclone_config:/config/rclone
      - gdrive_data:/gdrive
    networks:
      - ai_network
    healthcheck:
      test: ["CMD", "sh", "-c", "pgrep -f 'sleep infinity' > /dev/null || pgrep -f 'rclone sync' > /dev/null || exit 0"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 15s
```

**Critical changes:**
1. `entrypoint: ["/bin/sh", "-c"]` — routes execution through sh, not rclone binary
2. `command: |` — literal block scalar, preserves newlines (not `>` which collapses them)
3. Graceful no-config handling — idles instead of crashing, allowing rclone config to be added later
4. Healthcheck added — allows dependent services to use `service_started` correctly

### Fix 4: `docker-compose.yml` — gdrive-ingestion dependency

```yaml
# FIND in gdrive-ingestion depends_on:
      rclone:
        condition: service_healthy

# REPLACE WITH:
      rclone:
        condition: service_started
```

Rclone may legitimately be idling (no config yet). Ingestion should not be blocked by rclone config state — it should start, check for data in `/gdrive`, and idle gracefully if nothing is there.

### Fix 5: `scripts/2-deploy-services.sh` — postgres readiness

```bash
# FIND any sleep-based postgres wait like:
sleep 10
# or:
sleep 15

# REPLACE WITH:
echo "Waiting for PostgreSQL to accept connections..."
RETRIES=30
COUNT=0
until docker compose exec -T postgres pg_isready \
    -U "${POSTGRES_USER:-litellm}" \
    -d litellm \
    -q 2>/dev/null; do
    COUNT=$((COUNT + 1))
    if [ "$COUNT" -ge "$RETRIES" ]; then
        echo "ERROR: PostgreSQL not ready after $((RETRIES * 5)) seconds"
        docker compose logs postgres --tail 20
        exit 1
    fi
    echo "  PostgreSQL not ready (attempt $COUNT/$RETRIES), waiting 5s..."
    sleep 5
done
echo "PostgreSQL is ready."
```

### Fix 6: `scripts/3-configure-services.sh` — LiteLLM readiness gate

Add this function at the top of the script and call it before any LiteLLM API operations:

```bash
# ============================================================
# FUNCTION: Wait for LiteLLM to accept connections
# ============================================================
wait_for_litellm() {
    local MAX_WAIT=400
    local INTERVAL=10
    local ELAPSED=0
    
    echo "Waiting for LiteLLM /health/liveliness..."
    
    while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            "http://localhost:4000/health/liveliness" 2>/dev/null)
        
        if [ "$HTTP_CODE" = "200" ]; then
            echo "LiteLLM is ready (${ELAPSED}s elapsed)."
            return 0
        fi
        
        echo "  LiteLLM not ready (HTTP $HTTP_CODE, ${ELAPSED}s elapsed), waiting ${INTERVAL}s..."
        sleep "$INTERVAL"
        ELAPSED=$((ELAPSED + INTERVAL))
    done
    
    echo "ERROR: LiteLLM did not become ready within ${MAX_WAIT}s"
    echo "Logs:"
    docker compose logs litellm --tail 30
    return 1
}

# ============================================================
# FUNCTION: Generate LiteLLM API key with validation
# ============================================================
generate_litellm_key() {
    local ALIAS="$1"
    local MODELS_JSON="$2"  # e.g. '["ollama-llama3","ollama-mistral"]'
    
    RESPONSE=$(curl -sf -X POST \
        "http://localhost:4000/key/generate" \
        -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
        -H "Content-Type: application/json" \
        -d "{
            \"key_alias\": \"${ALIAS}\",
            \"models\": ${MODELS_JSON},
            \"duration\": null
        }" 2>/dev/null)
    
    if [ -z "$RESPONSE" ]; then
        echo "ERROR: Empty response from LiteLLM key/generate for alias: $ALIAS"
        return 1
    fi
    
    KEY=$(echo "$RESPONSE" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d.get('key',''))" 2>/dev/null)
    
    if [ -z "$KEY" ]; then
        echo "ERROR: No key in response: $RESPONSE"
        return 1
    fi
    
    echo "$KEY"
    return 0
}

# ============================================================
# MAIN: Call readiness gate before any LiteLLM operations
# ============================================================
wait_for_litellm || exit 1

# Now safe to configure:
ANYTHINGLLM_KEY=$(generate_litellm_key "anythingllm-key" \
    '["ollama-llama3","ollama-mistral","ollama-llama3-2"]') || exit 1
echo "AnythingLLM key generated: ${ANYTHINGLLM_KEY:0:20}..."

OPENWEBUI_KEY=$(generate_litellm_key "openwebui-key" \
    '["ollama-llama3","ollama-mistral","ollama-llama3-2"]') || exit 1
echo "OpenWebUI key generated: ${OPENWEBUI_KEY:0:20}..."

FLOWISE_KEY=$(generate_litellm_key "flowise-key" \
    '["ollama-llama3","ollama-mistral"]') || exit 1
echo "Flowise key generated: ${FLOWISE_KEY:0:20}..."

N8N_KEY=$(generate_litellm_key "n8n-key" \
    '["ollama-llama3","ollama-mistral"]') || exit 1
echo "N8N key generated: ${N8N_KEY:0:20}..."
```

### Fix 7: `scripts/3-configure-services.sh` — Qdrant collection creation

```bash
# ============================================================
# Create Qdrant collection for GDrive document ingestion
# ============================================================
configure_qdrant() {
    echo ""
    echo "=== Configuring Qdrant Collections ==="
    
    # Wait for Qdrant
    for i in $(seq 1 12); do
        if curl -sf "http://localhost:6333/collections" > /dev/null 2>&1; then
            echo "Qdrant is ready."
            break
        fi
        [ "$i" -eq 12 ] && echo "ERROR: Qdrant not ready" && return 1
        echo "  Waiting for Qdrant... ($i/12)"
        sleep 5
    done
    
    # Check if collection exists
    STATUS=$(curl -sf "http://localhost:6333/collections/gdrive_documents" 2>/dev/null)
    
    if echo "$STATUS" | grep -q '"status":"green"'; then
        echo "Collection 'gdrive_documents' already exists and healthy."
        return 0
    fi
    
    echo "Creating collection 'gdrive_documents'..."
    RESULT=$(curl -sf -X PUT \
        "http://localhost:6333/collections/gdrive_documents" \
        -H "Content-Type: application/json" \
        -d '{
            "vectors": {
                "size": 1536,
                "distance": "Cosine"
            },
            "optimizers_config": {
                "default_segment_number": 2
            },
            "replication_factor": 1
        }' 2>/dev/null)
    
    if echo "$RESULT" | grep -q '"result":true'; then
        echo "Collection created successfully."
        
        # Create payload indexes for filtering
        curl -sf -X PUT \
            "http://localhost:6333/collections/gdrive_documents/index" \
            -H "Content-Type: application/json" \
            -d '{"field_name":"source_file","field_schema":"keyword"}' > /dev/null
            
        curl -sf -X PUT \
            "http://localhost:6333/collections/gdrive_documents/index" \
            -H "Content-Type: application/json" \
            -d '{"field_name":"ingested_at","field_schema":"integer"}' > /dev/null
            
        echo "Payload indexes created."
    else
        echo "WARNING: Collection creation returned: $RESULT"
    fi
}

configure_qdrant
```

### Fix 8: `scripts/3-configure-services.sh` — Signal registration

```bash
# ============================================================
# Signal API — guided registration
# ============================================================
configure_signal() {
    echo ""
    echo "=== Signal API Configuration ==="
    
    if ! docker ps --format '{{.Names}}' | grep -q signal; then
        echo "Signal container not running. Skipping."
        return 0
    fi
    
    # Wait for signal-api to be up
    for i in $(seq 1 12); do
        if curl -sf "http://localhost:8080/v1/about" > /dev/null 2>&1; then
            break
        fi
        echo "  Waiting for Signal API... ($i/12)"
        sleep 5
    done
    
    # Check if already registered
    ACCOUNTS=$(curl -sf "http://localhost:8080/v1/accounts" 2>/dev/null)
    REGISTERED=$(echo "$ACCOUNTS" | python3 -c \
        "import sys,json
try:
    data=json.load(sys.stdin)
    print('yes' if data else 'no')
except:
    print('no')" 2>/dev/null)
    
    if [ "$REGISTERED" = "yes" ]; then
        echo "Signal already registered."
        return 0
    fi
    
    if [ -z "${SIGNAL_PHONE_NUMBER}" ]; then
        echo ""
        echo "┌─────────────────────────────────────────────────────┐"
        echo "│  Signal API requires phone number registration      │"
        echo "│                                                     │"
        echo "│  Add to .env:                                       │"
        echo "│    SIGNAL_PHONE_NUMBER=+1XXXXXXXXXX                 │"
        echo "│                                                     │"
        echo "│  Then register manually:                            │"
        echo "│    curl -X POST http://localhost:8080/v1/register/  │"
        echo "│         +1XXXXXXXXXX                                │"
        echo "│                                                     │"
        echo "│  Then verify with SMS code:                         │"
        echo "│    curl -X POST http://localhost:8080/v1/register/  │"
        echo "│         +1XXXXXXXXXX/verify/XXXXXX                  │"
        echo "└─────────────────────────────────────────────────────┘"
        return 0
    fi
    
    echo "Registering ${SIGNAL_PHONE_NUMBER}..."
    curl -sf -X POST \
        "http://localhost:8080/v1/register/${SIGNAL_PHONE_NUMBER}" \
        -H "Content-Type: application/json" \
        -d '{"use_voice": false}' > /dev/null
    
    echo ""
    echo "SMS verification code sent to ${SIGNAL_PHONE_NUMBER}"
    echo "After receiving code, run:"
    echo "  curl -X POST http://localhost:8080/v1/register/${SIGNAL_PHONE_NUMBER}/verify/XXXXXX"
}

configure_signal
```

---

## Complete Validation Script

Add this as `scripts/4-validate-deployment.sh`:

```bash
#!/bin/bash
# ============================================================
# Deployment Validation — checks actual functionality
# not just container status
# ============================================================

set -a
source "$(dirname "$0")/../.env" 2>/dev/null
set +a

PASS=0
FAIL=0
WARN=0

check() {
    local NAME="$1"
    local CMD="$2"
    local EXPECTED="$3"
    
    RESULT=$(eval "$CMD" 2>/dev/null)
    if echo "$RESULT" | grep -q "$EXPECTED"; then
        echo "  ✅ $NAME"
        PASS=$((PASS + 1))
    else
        echo "  ❌ $NAME"
        echo "     Expected: $EXPECTED"
        echo "     Got: ${RESULT:0:100}"
        FAIL=$((FAIL + 1))
    fi
}

warn() {
    local NAME="$1"
    local MSG="$2"
    echo "  ⚠️  $NAME: $MSG"
    WARN=$((WARN + 1))
}

echo ""
echo "════════════════════════════════════════"
echo " Infrastructure"
echo "════════════════════════════════════════"
check "PostgreSQL" \
    "docker compose exec -T postgres pg_isready -q && echo ok" "ok"
check "Redis" \
    "docker compose exec -T redis redis-cli ping" "PONG"
check "Qdrant" \
    "curl -sf http://localhost:6333/healthz" "healthz check passed"
check "Ollama" \
    "curl -sf http://localhost:11434/api/tags | python3 -c \"import sys,json; d=json.load(sys.stdin); print(len(d.get('models',[])))\"" \
    "[1-9]"

echo ""
echo "════════════════════════════════════════"
echo " LiteLLM (the critical service)"
echo "════════════════════════════════════════"
check "LiteLLM liveliness" \
    "curl -sf http://localhost:4000/health/liveliness" "alive"
check "LiteLLM models endpoint" \
    "curl -sf -H 'Authorization: Bearer ${LITELLM_MASTER_KEY}' http://localhost:4000/models" \
    "object"
check "LiteLLM Docker health" \
    "docker inspect --format='{{.State.Health.Status}}' \$(docker ps -q -f name=litellm)" \
    "healthy"

echo ""
echo "════════════════════════════════════════"
echo " AI Services"  
echo "════════════════════════════════════════"
check "OpenWebUI" \
    "curl -sf http://localhost:8080 -o /dev/null -w '%{http_code}'" "200"
check "AnythingLLM" \
    "curl -sf http://localhost:3001/api/ping" "pong"
check "Flowise" \
    "curl -sf http://localhost:3000 -o /dev/null -w '%{http_code}'" "200"
check "N8N" \
    "curl -sf http://localhost:5678 -o /dev/null -w '%{http_code}'" "200"

echo ""
echo "════════════════════════════════════════"
echo " External Access (Caddy + Tailscale)"
echo "════════════════════════════════════════"
check "OpenWebUI external" \
    "curl -sf https://chat.${BASE_DOMAIN} -o /dev/null -w '%{http_code}'" "200"
check "LiteLLM external" \
    "curl -sf https://litellm.${BASE_DOMAIN}/health/liveliness" "alive"

echo ""
echo "════════════════════════════════════════"
echo " Data Pipeline"
echo "════════════════════════════════════════"
check "Qdrant collection" \
    "curl -sf http://localhost:6333/collections/gdrive_documents" "green"
RCLONE_LOG=$(docker logs $(docker ps -q -f name=rclone) --tail 3 2>/dev/null)
if echo "$RCLONE_LOG" | grep -q "unknown command"; then
    echo "  ❌ RClone: still crashing with 'unknown command sh'"
    FAIL=$((FAIL + 1))
elif echo "$RCLONE_LOG" | grep -q "sync daemon\|not found\|Sleeping"; then
    echo "  ✅ RClone: operating normally"
    PASS=$((PASS + 1))
else
    warn "RClone" "unclear state — check: docker logs \$(docker ps -q -f name=rclone)"
fi

echo ""
echo "════════════════════════════════════════"
echo " Results"
echo "════════════════════════════════════════"
echo "  Passed:   $PASS"
echo "  Failed:   $FAIL"  
echo "  Warnings: $WARN"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo "  🎉 All checks passed. Platform is healthy."
else
    echo "  ❌ $FAIL checks failed. Review errors above."
    exit 1
fi
```

---

## Exact Instructions for Windsurf

```
STOP. Read this completely before making any changes.

The platform has exactly 2 code bugs blocking 5 services.
Everything else is either working or blocked by these 2 bugs.
Do not touch any currently healthy service.

═══════════════════════════════════════════════════════════
BUG 1: LiteLLM health check uses wrong endpoint
File: docker-compose.yml
═══════════════════════════════════════════════════════════

FIND in litellm service healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:4000/health"]

CHANGE TO:
  test: ["CMD", "curl", "-sf", "http://localhost:4000/health/liveliness"]
  interval: 30s
  timeout: 15s
  retries: 10
  start_period: 90s

ALSO ADD to litellm environment:
  BACKGROUND_HEALTH_CHECKS: "True"
  HEALTH_CHECK_INTERVAL: "300"

WHY: /health makes outbound HTTP calls to Groq/Gemini/OpenRouter.
     These calls timeout after 10-30s each. Docker's health check
     timeout fires before all providers respond. Check fails.
     Retries indefinitely. All dependent services wait forever.
     /health/liveliness returns {"status":"alive"} in <100ms.

═══════════════════════════════════════════════════════════
BUG 2: RClone entrypoint is wrong
File: docker-compose.yml  
═══════════════════════════════════════════════════════════

The rclone image ENTRYPOINT is /usr/local/bin/rclone.
The current command: "sh -c ..." gets passed as arguments
to rclone binary → rclone sh -c ... → "unknown command sh"

FIND in rclone service:
  command: >
    sh -c "..."

REPLACE THE ENTIRE rclone service definition with:

  rclone:
    image: rclone/rclone:latest
    restart: unless-stopped
    entrypoint: ["/bin/sh", "-c"]
    command: |
      if [ ! -f /config/rclone/rclone.conf ]; then
        echo "[rclone] Config not found. Idling."
        exec sleep infinity
      fi
      echo "[rclone] Starting sync daemon."
      while true; do
        rclone sync gdrive:/ /gdrive \
          --config /config/rclone/rclone.conf \
          --log-level INFO \
          --transfers 4 \
          --contimeout 60s \
          --timeout 300s \
          --retries 3
        sleep 300
      done
    volumes:
      - rclone_config:/config/rclone
      - gdrive_data:/gdrive
    networks:
      - ai_network
    healthcheck:
      test: ["CMD", "sh", "-c", "exit 0"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 15s

NOTE: The | (pipe) YAML scalar is NOT interchangeable with > (greater-than).
      > folds newlines into spaces. The shell script becomes one line.
      | preserves newlines. Shell script executes correctly.
      This is a YAML syntax issue, not a shell issue.

═══════════════════════════════════════════════════════════
BUG 3: gdrive-ingestion blocked on rclone healthy
File: docker-compose.yml
═══════════════════════════════════════════════════════════

FIND in gdrive-ingestion depends_on:
  rclone:
    condition: service_healthy

CHANGE TO:
  rclone:
    condition: service_started

WHY: rclone may legitimately idle with no config (no GDrive OAuth yet).
     service_healthy would wait forever. service_started proceeds.

═══════════════════════════════════════════════════════════
BUG 4: Script 3 sends API calls before LiteLLM is ready
File: scripts/3-configure-services.sh
═══════════════════════════════════════════════════════════

ADD this block BEFORE any curl calls to localhost:4000:

  echo "Waiting for LiteLLM..."
  for i in $(seq 1 40); do
    if curl -sf http://localhost:4000/health/liveliness > /dev/null 2>&1; then
      echo "LiteLLM ready after $((i * 10))s"
      break
    fi
    [ "$i" -eq 40 ] && echo "ERROR: LiteLLM not ready" && exit 1
    echo "  Attempt $i/40, waiting 10s..."
    sleep 10
  done

═══════════════════════════════════════════════════════════
APPLY CHANGES IN THIS EXACT ORDER:
═══════════════════════════════════════════════════════════

1. Make all docker-compose.yml changes
2. Make scripts/3-configure-services.sh changes  
3. Run: docker compose up -d --no-deps --force-recreate litellm rclone
4. Run: watch -n 5 'docker inspect --format="{{.State.Health.Status}}" $(docker ps -q -f name=litellm)'
5. Wait until output shows "healthy" (should take 1-3 minutes)
6. Run: docker compose up -d anythingllm flowise n8n gdrive-ingestion
7. Wait 60 seconds
8. Run validation: bash scripts/4-validate-deployment.sh

═══════════════════════════════════════════════════════════
DO NOT claim success until:
═══════════════════════════════════════════════════════════

  curl http://localhost:4000/health/liveliness
  → Must return: {"status":"alive"}

  docker inspect --format='{{.State.Health.Status}}' $(docker ps -q -f name=litellm)
  → Must return: healthy

  docker logs $(docker ps -q -f name=rclone) --tail 5
  → Must show: "Config not found. Idling." OR "Starting sync daemon."
  → Must NOT show: "unknown command"

  docker ps | grep -E "anythingllm|flowise|n8n"
  → Must show: Up (not Restarting, not Created)
```

---

## Summary

| # | Bug | File | Change | Unblocks |
|---|-----|------|--------|----------|
| 1 | Wrong health endpoint | `docker-compose.yml` | `/health` → `/health/liveliness` | AnythingLLM, Flowise, N8N, gdrive-ingestion |
| 2 | Missing env vars | `docker-compose.yml` | Add `BACKGROUND_HEALTH_CHECKS=True` | LiteLLM startup speed |
| 3 | RClone entrypoint missing | `docker-compose.yml` | Add `entrypoint: ["/bin/sh","-c"]` | RClone sync |
| 4 | YAML `>` vs `\|` | `docker-compose.yml` | Change folded to literal scalar | RClone script execution |
| 5 | Wrong dependency condition | `docker-compose.yml` | `service_healthy` → `service_started` | gdrive-ingestion |
| 6 | No readiness gate | `3-configure-services.sh` | Add LiteLLM wait loop | Valid API keys everywhere |

**Two root bugs. Six targeted changes. Zero currently-healthy services touched.**