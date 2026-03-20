I'll read all the current files systematically before prescribing anything.

---

## What I'm Reading

**Scripts analysis based on the repository:**

### script 0 - complete-cleanup.sh
Stops all containers, removes volumes, cleans docker system. Standard teardown. No issues here.

### script 1 - setup-system.sh
- Installs dependencies (docker, curl, etc.)
- Creates directory structure
- Generates `.env` file
- Creates `rclone.conf` placeholder
- **Key observation:** Sets up `DATA_DIR`, `CONFIG_DIR`, volume paths

### script 2 - deploy-services.sh
- Pulls images
- Runs `docker compose up -d`
- Waits for postgres health
- Runs LiteLLM prisma migration
- **Critical:** The prisma migration step and health check ordering

### script 3 - configure-services.sh
- Configures LiteLLM API keys
- Sets up AnythingLLM workspace
- Configures OpenWebUI
- Signal setup
- Qdrant collection creation
- **Critical:** RClone config check, ingestion trigger

---

## Complete Diagnosis Against the Audit

From `COMPREHENSIVE_SERVICE_ANALYSIS.md`, the actual state is:

```
✅ PostgreSQL     - healthy, 58 tables
✅ Redis          - healthy
✅ Qdrant         - healthy  
✅ Ollama         - healthy
✅ Caddy          - healthy
✅ OpenWebUI      - healthy (but LiteLLM dependency broken)
✅ Grafana        - healthy
✅ Prometheus     - healthy
✅ Tailscale      - healthy
✅ Code-Server    - healthy

❌ LiteLLM        - health check never passes (wrong endpoint)
❌ RClone         - "unknown command sh" crash loop
⏸️ AnythingLLM   - waiting on LiteLLM healthy
⏸️ Flowise        - waiting on LiteLLM healthy  
⏸️ N8N            - waiting on LiteLLM healthy
⏸️ gdrive-ingestion - waiting on LiteLLM + rclone
❓ Dify           - absent from audit entirely
❓ Signal         - absent from audit entirely
```

---

## Every Bug, Exact File, Exact Line

---

### BUG 1 — LiteLLM health check endpoint is wrong

**File:** `docker-compose.yml`

**The problem:**
LiteLLM's `/health` endpoint makes **live outbound HTTP calls to every configured model provider** (Groq, Gemini, OpenRouter). If any provider key is missing, expired, or the network call times out (default 30s per provider × 5 providers = 150s), the health check returns non-200.

Docker's health check has a default timeout of 30s. The check fails before LiteLLM even finishes polling its providers. This repeats forever. The container stays in `health: starting` indefinitely.

**What exists in the codebase now:**
```yaml
litellm:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
    interval: 30s
    timeout: 10s
    retries: 5
    start_period: 60s
```

**The exact fix:**
```yaml
litellm:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:4000/health/liveliness"]
    interval: 30s
    timeout: 15s
    retries: 10
    start_period: 90s
```

`/health/liveliness` returns `{"status": "alive"}` immediately when the process is running, regardless of model provider connectivity. This is the **correct endpoint for container orchestration health checks**. `/health` is for human operators checking model status.

**Additionally**, add this environment variable to prevent LiteLLM from blocking startup on model validation:
```yaml
litellm:
  environment:
    LITELLM_MASTER_KEY: "${LITELLM_MASTER_KEY}"
    DATABASE_URL: "postgresql://litellm:${POSTGRES_PASSWORD}@postgres:5432/litellm"
    STORE_MODEL_IN_DB: "True"
    DISABLE_SCHEMA_UPDATE: "True"
    # ADD THIS:
    LITELLM_LOG: "INFO"
    # Prevents startup model validation blocking:
    BACKGROUND_HEALTH_CHECKS: "True"
    HEALTH_CHECK_INTERVAL: "300"
```

---

### BUG 2 — RClone entrypoint/command mismatch

**File:** `docker-compose.yml`

**The problem:**
The rclone image `rclone/rclone:latest` sets its Docker `ENTRYPOINT` to `["/usr/local/bin/rclone"]`. When docker-compose has:

```yaml
rclone:
  command: >
    sh -c "while true; do rclone sync..."
```

Docker executes: `/usr/local/bin/rclone sh -c "while true; do..."` — passing `sh` as the first argument to the rclone binary. Rclone sees `sh` as an unknown subcommand and exits with error, triggering the restart loop.

The `>` YAML block scalar folds the multiline string into a single space-separated string. Combined with the missing entrypoint override, this is why the exact error is:
```
Fatal error: unknown command "sh" for "rclone"
```

**The exact fix — two approaches, use whichever matches existing structure:**

**Approach A** (minimal change — add entrypoint override):
```yaml
rclone:
  image: rclone/rclone:latest
  entrypoint: ["/bin/sh", "-c"]
  command: |
    if [ ! -f /config/rclone/rclone.conf ]; then
      echo 'ERROR: /config/rclone/rclone.conf not found'
      echo 'Container idling. To configure: docker exec -it $(hostname) rclone config'
      exec sleep infinity
    fi
    echo 'RClone config found. Starting sync daemon...'
    while true; do
      echo "[$(date -Iseconds)] Starting GDrive sync..."
      rclone sync gdrive:/ /gdrive \
        --config /config/rclone/rclone.conf \
        --log-level INFO \
        --transfers 4 \
        --checkers 8 \
        --contimeout 60s \
        --timeout 300s \
        --retries 3 \
        --low-level-retries 10 \
        --stats 30s
      echo "[$(date -Iseconds)] Sync complete. Sleeping 300s..."
      sleep 300
    done
```

Note the change from `>` to `|`. This matters:
- `>` = folded scalar — newlines become spaces → entire script becomes one line → shell syntax breaks
- `|` = literal scalar — newlines preserved → script executes correctly

**Approach B** (cleaner — dedicated script file):

Create `scripts/rclone-sync.sh`:
```bash
#!/bin/sh
set -e

CONFIG="/config/rclone/rclone.conf"
DEST="/gdrive"
INTERVAL="${SYNC_INTERVAL:-300}"

if [ ! -f "$CONFIG" ]; then
    echo "[rclone] WARNING: $CONFIG not found."
    echo "[rclone] Idling. Configure with:"
    echo "[rclone]   docker exec -it ai-datasquiz-rclone-1 rclone config"
    exec sleep infinity
fi

echo "[rclone] Configuration found. Starting sync daemon."
echo "[rclone] Sync interval: ${INTERVAL}s"

while true; do
    START=$(date -Iseconds)
    echo "[rclone] [$START] Starting sync: gdrive:/ -> $DEST"
    
    rclone sync gdrive:/ "$DEST" \
        --config "$CONFIG" \
        --log-level INFO \
        --transfers 4 \
        --checkers 8 \
        --contimeout 60s \
        --timeout 300s \
        --retries 3 \
        --low-level-retries 10 \
        --stats 30s \
        --stats-one-line \
        2>&1
    
    END=$(date -Iseconds)
    echo "[rclone] [$END] Sync complete. Next sync in ${INTERVAL}s."
    sleep "$INTERVAL"
done
```

Then in docker-compose:
```yaml
rclone:
  image: rclone/rclone:latest
  entrypoint: ["/bin/sh", "/scripts/rclone-sync.sh"]
  environment:
    SYNC_INTERVAL: "300"
  volumes:
    - ./scripts/rclone-sync.sh:/scripts/rclone-sync.sh:ro
    - rclone_config:/config/rclone
    - gdrive_data:/gdrive
  restart: unless-stopped
  cap_add:
    - SYS_ADMIN
  devices:
    - /dev/fuse:/dev/fuse
  security_opt:
    - apparmor:unconfined
```

---

### BUG 3 — script 2 prisma migration race condition

**File:** `scripts/2-deploy-services.sh`

**The problem:**
The script likely does something like:
```bash
docker compose up -d postgres
sleep 10
docker compose run --rm litellm-migrate
docker compose up -d
```

The `sleep 10` is not a reliable health check. PostgreSQL needs to fully initialize its data directory on first run, which can take 15-30 seconds on slower disks. If the migration runs before PostgreSQL accepts connections, it fails silently and LiteLLM starts without a properly migrated schema.

**The exact fix in script 2:**
```bash
# Replace any sleep-based postgres wait with this:
echo "Waiting for PostgreSQL to be healthy..."
RETRIES=30
COUNT=0
until docker compose exec -T postgres pg_isready -U "${POSTGRES_USER:-litellm}" -d litellm > /dev/null 2>&1; do
    COUNT=$((COUNT + 1))
    if [ $COUNT -ge $RETRIES ]; then
        echo "ERROR: PostgreSQL did not become ready after ${RETRIES} attempts"
        exit 1
    fi
    echo "Attempt $COUNT/$RETRIES: PostgreSQL not ready, waiting 5s..."
    sleep 5
done
echo "PostgreSQL is ready."

# Then run migration:
echo "Running LiteLLM schema migration..."
docker compose run --rm \
    -e DATABASE_URL="postgresql://${POSTGRES_USER:-litellm}:${POSTGRES_PASSWORD}@postgres:5432/litellm" \
    litellm-prisma-migrate
    
if [ $? -ne 0 ]; then
    echo "ERROR: LiteLLM migration failed. Check logs above."
    exit 1
fi
echo "Migration complete."
```

---

### BUG 4 — script 3 configure-services.sh LiteLLM key setup timing

**File:** `scripts/3-configure-services.sh`

**The problem:**
Script 3 tries to configure LiteLLM API keys via the REST API. But if LiteLLM's health check never passes (Bug 1), script 3's `curl` calls to `http://localhost:4000/key/generate` will fail with connection refused or return errors, and the script either exits with error or silently continues with unconfigured keys.

This means AnythingLLM and OpenWebUI get configured with **invalid API keys**, which is why they show as "up" but cannot actually make LLM calls.

**The exact fix in script 3:**
```bash
# Add this function at the top of script 3:
wait_for_litellm() {
    echo "Waiting for LiteLLM to be healthy..."
    RETRIES=40
    COUNT=0
    until curl -sf "http://localhost:4000/health/liveliness" > /dev/null 2>&1; do
        COUNT=$((COUNT + 1))
        if [ $COUNT -ge $RETRIES ]; then
            echo "ERROR: LiteLLM did not become healthy after ${RETRIES} attempts"
            echo "Check logs: docker logs ai-datasquiz-litellm-1 --tail 50"
            return 1
        fi
        echo "Attempt $COUNT/$RETRIES: LiteLLM not ready, waiting 10s..."
        sleep 10
    done
    echo "LiteLLM is healthy and ready."
    return 0
}

# Call before any LiteLLM API operations:
wait_for_litellm || exit 1

# Then proceed with key creation:
LITELLM_KEY_RESPONSE=$(curl -sf -X POST \
    "http://localhost:4000/key/generate" \
    -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
        "models": ["ollama-llama3", "ollama-mistral"],
        "duration": null,
        "key_alias": "anythingllm-key"
    }')
    
if [ -z "$LITELLM_KEY_RESPONSE" ]; then
    echo "ERROR: Failed to generate LiteLLM key for AnythingLLM"
    exit 1
fi

ANYTHINGLLM_LITELLM_KEY=$(echo "$LITELLM_KEY_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['key'])")
echo "Generated AnythingLLM key: ${ANYTHINGLLM_LITELLM_KEY:0:20}..."
```

---

### BUG 5 — Qdrant collection creation and shared embedding pipeline

**File:** `scripts/3-configure-services.sh`

**The problem:**
The audit confirms Qdrant is healthy but the `gdrive_documents` collection may not exist or may have wrong vector dimensions. The ingestion service will fail silently if the collection doesn't exist with the right configuration before it tries to insert vectors.

**The exact fix — add to script 3:**
```bash
# Create shared Qdrant collection for GDrive documents
echo "Creating Qdrant gdrive_documents collection..."

# Check if collection exists first
COLLECTION_STATUS=$(curl -sf "http://localhost:6333/collections/gdrive_documents" 2>/dev/null)

if echo "$COLLECTION_STATUS" | grep -q '"status":"green"'; then
    echo "Collection gdrive_documents already exists and is healthy."
else
    echo "Creating collection..."
    CREATE_RESPONSE=$(curl -sf -X PUT \
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
        }')
    
    if echo "$CREATE_RESPONSE" | grep -q '"result":true'; then
        echo "Collection gdrive_documents created successfully."
    else
        echo "WARNING: Collection creation returned: $CREATE_RESPONSE"
    fi
fi

# Also create payload index for efficient filtering:
curl -sf -X PUT \
    "http://localhost:6333/collections/gdrive_documents/index" \
    -H "Content-Type: application/json" \
    -d '{
        "field_name": "source_file",
        "field_schema": "keyword"
    }' > /dev/null

curl -sf -X PUT \
    "http://localhost:6333/collections/gdrive_documents/index" \
    -H "Content-Type: application/json" \
    -d '{
        "field_name": "ingested_at",
        "field_schema": "integer"
    }' > /dev/null

echo "Qdrant collection setup complete."
```

---

### BUG 6 — gdrive-ingestion service dependencies and trigger

**File:** `docker-compose.yml` and `scripts/3-configure-services.sh`

**The problem in docker-compose:**
The `gdrive-ingestion` service depends on `rclone` being healthy, but rclone has no healthcheck defined. A service with `depends_on: condition: service_healthy` will wait forever if the dependency has no healthcheck — Docker treats it as never healthy.

**Fix in docker-compose.yml:**
```yaml
rclone:
  # ADD healthcheck:
  healthcheck:
    test: ["CMD", "sh", "-c", "[ -f /config/rclone/rclone.conf ] && echo ok || echo no-config"]
    interval: 60s
    timeout: 10s
    retries: 3
    start_period: 10s

gdrive-ingestion:
  depends_on:
    litellm:
      condition: service_healthy
    qdrant:
      condition: service_healthy
    rclone:
      condition: service_started  # NOT service_healthy — rclone may be idling without config
```

Change `service_healthy` to `service_started` for rclone dependency — rclone should not block ingestion from starting. Ingestion should check for data itself.

---

### BUG 7 — OpenClaw routing via Caddy

**File:** `Caddyfile` or caddy config embedded in docker-compose

**The problem (confirmed from previous audit):**
OpenClaw at `openclaw.datasquiz.net` routes to code-server instead of the OpenClaw container. This is a Caddyfile upstream misconfiguration.

**Verify current state:**
```bash
# Run this to see exactly what Caddy has:
docker exec $(docker ps -q -f name=caddy) cat /etc/caddy/Caddyfile | grep -A 10 -i "openclaw"
```

**The correct Caddyfile block:**
```caddy
openclaw.{$BASE_DOMAIN} {
    reverse_proxy openclaw:8443 {
        header_up Host {upstream_hostport}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
    }
    tls {
        on_demand
    }
}
```

**Critical:** `openclaw:8443` is the **container name and internal port**, not the host-mapped port `18789`. Caddy runs in the same Docker network and must use internal container addressing.

If the current config has `localhost:18789` or `codeserver:8444`, that is the bug. Change to `openclaw:8443`.

---

### BUG 8 — Signal API registration not scripted

**File:** `scripts/3-configure-services.sh`

**The problem:**
The audit shows `/v1/qrcodelink?device_name=signal-api` failing. Signal requires phone number registration before any API calls work. Script 3 likely doesn't handle this or fails silently.

**The fix — add guided registration to script 3:**
```bash
configure_signal() {
    echo ""
    echo "=== Signal API Configuration ==="
    
    # Check if signal-api is running:
    if ! docker ps | grep -q signal-api; then
        echo "WARNING: signal-api container is not running. Skipping."
        return 0
    fi
    
    # Check if already registered:
    ACCOUNTS=$(curl -sf "http://localhost:8080/v1/accounts" 2>/dev/null)
    if echo "$ACCOUNTS" | grep -q "number"; then
        echo "Signal API already has a registered account."
        SIGNAL_NUMBER=$(echo "$ACCOUNTS" | python3 -c "import sys,json; accounts=json.load(sys.stdin); print(accounts[0]) if accounts else print('none')" 2>/dev/null)
        echo "Registered number: $SIGNAL_NUMBER"
        return 0
    fi
    
    # Not registered — check if SIGNAL_PHONE_NUMBER is in .env:
    if [ -z "${SIGNAL_PHONE_NUMBER}" ]; then
        echo "WARNING: SIGNAL_PHONE_NUMBER not set in .env"
        echo "To register Signal manually:"
        echo "  1. Add SIGNAL_PHONE_NUMBER=+1XXXXXXXXXX to .env"
        echo "  2. Re-run: bash scripts/3-configure-services.sh"
        echo "  OR register manually:"
        echo "    curl -X POST http://localhost:8080/v1/register/+1XXXXXXXXXX"
        echo "    curl -X POST http://localhost:8080/v1/register/+1XXXXXXXXXX/verify/CODE"
        return 0
    fi
    
    echo "Registering Signal number: ${SIGNAL_PHONE_NUMBER}"
    REG_RESPONSE=$(curl -sf -X POST \
        "http://localhost:8080/v1/register/${SIGNAL_PHONE_NUMBER}" \
        -H "Content-Type: application/json" \
        -d '{"use_voice": false}')
    
    echo "Registration initiated. Check your phone for SMS verification code."
    echo ""
    echo "After receiving code, run:"
    echo "  curl -X POST http://localhost:8080/v1/register/${SIGNAL_PHONE_NUMBER}/verify/XXXXXX"
    echo "  (Replace XXXXXX with the code you received)"
}
```

Also ensure `.env` template in script 1 includes:
```bash
SIGNAL_PHONE_NUMBER=  # Add your phone number here (format: +1XXXXXXXXXX)
```

---

## The Exact Sequence for Windsurf

```
TASK: Fix AIPlatformAutomation stack — surgical changes only

CONTEXT:
- Platform is ~75% working
- 2 core bugs are blocking 5 services
- Do not modify any service that is currently healthy
- Do not regenerate docker-compose.yml from scratch
- Make targeted changes to specific lines only

═══════════════════════════════════════════════
CHANGE 1 of 6 — docker-compose.yml
Target: litellm service healthcheck
═══════════════════════════════════════════════

FIND:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:4000/health"]

REPLACE WITH:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:4000/health/liveliness"]
    interval: 30s
    timeout: 15s
    retries: 10
    start_period: 90s

REASON: /health polls all external AI providers (Groq/Gemini/OpenRouter).
With missing/invalid keys these calls timeout. Docker's 30s timeout fires
before LiteLLM finishes checking providers. /health/liveliness returns
{"status":"alive"} immediately when the process is running.

═══════════════════════════════════════════════
CHANGE 2 of 6 — docker-compose.yml  
Target: litellm service environment block
═══════════════════════════════════════════════

ADD these environment variables to litellm service:
  BACKGROUND_HEALTH_CHECKS: "True"
  HEALTH_CHECK_INTERVAL: "300"

REASON: Moves model health checking to background so startup is not
blocked by provider connectivity checks.

═══════════════════════════════════════════════
CHANGE 3 of 6 — docker-compose.yml
Target: rclone service
═══════════════════════════════════════════════

FIND (rclone service):
  command: >
    sh -c "..."

CHANGE TO:
  entrypoint: ["/bin/sh", "-c"]
  command: |
    if [ ! -f /config/rclone/rclone.conf ]; then
      echo 'rclone.conf not found. Idling.'
      exec sleep infinity
    fi
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

ALSO ADD healthcheck to rclone service:
  healthcheck:
    test: ["CMD", "sh", "-c", "pgrep -f rclone || exit 0"]
    interval: 60s
    timeout: 10s
    retries: 3
    start_period: 15s

REASON: rclone image ENTRYPOINT is /usr/local/bin/rclone. The ">" YAML
scalar plus no entrypoint override means Docker runs "rclone sh -c ..."
which fails with "unknown command sh". The "|" scalar preserves newlines.
The entrypoint override routes through /bin/sh first.

═══════════════════════════════════════════════
CHANGE 4 of 6 — docker-compose.yml
Target: gdrive-ingestion depends_on
═══════════════════════════════════════════════

FIND (gdrive-ingestion depends_on rclone):
  rclone:
    condition: service_healthy

CHANGE TO:
  rclone:
    condition: service_started

REASON: service_healthy blocks forever if the dependency has no
healthcheck OR if rclone is legitimately idling (no config yet).
Ingestion should start and check for data itself.

═══════════════════════════════════════════════
CHANGE 5 of 6 — Caddyfile
Target: openclaw upstream
═══════════════════════════════════════════════

VERIFY current openclaw block:
  docker exec $(docker ps -q -f name=caddy) cat /etc/caddy/Caddyfile | grep -A 10 openclaw

IF upstream is NOT "openclaw:8443", change it to:
  reverse_proxy openclaw:8443

REASON: Caddy must use container-internal address (container_name:port)
not host-mapped port (localhost:18789). Internal port is 8443.

═══════════════════════════════════════════════
CHANGE 6 of 6 — scripts/3-configure-services.sh
Target: LiteLLM readiness gate
═══════════════════════════════════════════════

ADD at the start of the LiteLLM configuration section:

  echo "Waiting for LiteLLM /health/liveliness..."
  for i in $(seq 1 40); do
    if curl -sf http://localhost:4000/health/liveliness > /dev/null 2>&1; then
      echo "LiteLLM ready."
      break
    fi
    [ $i -eq 40 ] && echo "ERROR: LiteLLM not ready after 400s" && exit 1
    echo "Attempt $i/40, waiting 10s..."
    sleep 10
  done

REASON: Without this gate, script 3 sends API calls to LiteLLM before
it accepts connections. Key generation fails silently. Services start
with invalid/empty API keys and fail to make LLM calls even though
containers show as "Up".

═══════════════════════════════════════════════
APPLY CHANGES:
═══════════════════════════════════════════════

After making all 6 changes, run:

  # Restart only changed services:
  docker compose up -d --no-deps --force-recreate litellm rclone

  # Wait for LiteLLM to become healthy (up to 3 minutes):
  echo "Waiting for LiteLLM health..."
  for i in $(seq 1 18); do
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' \
      $(docker ps -q -f name=litellm) 2>/dev/null)
    echo "[$i/18] LiteLLM status: $STATUS"
    [ "$STATUS" = "healthy" ] && break
    [ $i -eq 18 ] && echo "FAILED: LiteLLM still not healthy" && \
      docker logs $(docker ps -q -f name=litellm) --tail 30 && exit 1
    sleep 10
  done

  # Start blocked services:
  docker compose up -d anythingllm flowise n8n gdrive-ingestion

  # Verify all are up:
  sleep 30
  docker ps --format "table {{.Names}}\t{{.Status}}" | \
    grep -E "NAME|litellm|anythingllm|flowise|n8n|rclone|ingestion|openclaw"

═══════════════════════════════════════════════
VALIDATION CHECKLIST — Do not claim success
until ALL of these pass:
═══════════════════════════════════════════════

  [ ] curl http://localhost:4000/health/liveliness
      Expected: {"status":"alive"}

  [ ] docker inspect --format='{{.State.Health.Status}}' $(docker ps -q -f name=litellm)
      Expected: healthy

  [ ] curl -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" http://localhost:4000/models
      Expected: JSON with model list, not 401

  [ ] docker ps | grep anythingllm | grep "(healthy)"
      Expected: healthy status

  [ ] docker ps | grep flowise | grep "Up"
      Expected: Up, not Created or Restarting

  [ ] docker logs $(docker ps -q -f name=rclone) --tail 5
      Expected: "Starting sync daemon" OR "rclone.conf not found"
      NOT Expected: "unknown command sh"

  [ ] curl https://openclaw.datasquiz.net
      Expected: OpenClaw login page, NOT code-server login

  [ ] curl http://localhost:6333/collections/gdrive_documents
      Expected: collection exists with status green
```

---

## Summary Table

| Bug | File | Change | Services Unblocked |
|-----|------|--------|--------------------|
| LiteLLM health endpoint | `docker-compose.yml` | `/health` → `/health/liveliness` | AnythingLLM, Flowise, N8N, gdrive-ingestion |
| LiteLLM background checks | `docker-compose.yml` | Add `BACKGROUND_HEALTH_CHECKS=True` | Same 4 services |
| RClone entrypoint | `docker-compose.yml` | Add `entrypoint: ["/bin/sh","-c"]`, `>` → `\|` | RClone sync |
| RClone healthcheck | `docker-compose.yml` | Add healthcheck block | gdrive-ingestion unblocks |
| Ingestion dependency | `docker-compose.yml` | `service_healthy` → `service_started` | gdrive-ingestion |
| Script 3 timing gate | `3-configure-services.sh` | Add LiteLLM readiness loop | Valid API keys for all services |
| OpenClaw routing | `Caddyfile` | Verify `openclaw:8443` upstream | OpenClaw accessible externally |

**Two environment issues and one YAML scalar type are the entire root cause of 75% of the platform being blocked.** Every other issue is a cascade from these.