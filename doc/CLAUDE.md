# Final Sprint Blueprint — Surgical Fixes Only

## Reading the Actual State from the Audit

The audit is now much more honest than the previous "100% success" report. Let me map exactly what's true:

**Actually healthy:** PostgreSQL (58 tables ✅), Redis, Qdrant, Ollama, Caddy, OpenWebUI, Grafana, Prometheus, Tailscale, OpenClaw

**The blocking domino:** LiteLLM is "still initializing" after 37 seconds in the audit snapshot — but critically the audit was captured at 37 seconds uptime. The real question is: **does LiteLLM ever pass its health check?** Based on the pattern from the previous audit (13+ minutes, never healthy), the answer is no.

**Directly broken:** RClone — exact error identified in the audit log.

**Waiting on LiteLLM:** AnythingLLM, Flowise, N8N, gdrive-ingestion (5 services blocked by one fix).

---

## Reading the Current Codebase

Let me identify the exact files and lines before prescribing fixes.

---

## Issue 1: LiteLLM Health Check Never Passes

### The Real Diagnosis

The audit shows:
```
Initialization: ✅ Proxy initialized successfully
Models Loaded: 5 models configured
Health Check: HTTP endpoint not yet responding
```

LiteLLM **has** initialized. The proxy is running. The schema migration completed successfully (exit 0, 58 tables). So why does the health check never pass?

**The actual cause is the health check configuration itself, not LiteLLM startup.**

Look at what LiteLLM's `/health` endpoint actually does — it tries to **ping every configured model backend** before returning healthy. With 5 models including:
- `llama3.2:1b` (Ollama — fine)
- `llama3.2:3b` (Ollama — fine)  
- `llama3-groq` (Groq — needs valid API key)
- `gemini-pro` (Google — needs valid API key)
- `openrouter-mixtral` (OpenRouter — needs valid API key)

**If any external API key is missing, invalid, or the network call times out, `/health` returns non-200 and the Docker health check fails indefinitely.**

This is why the container shows `health: starting` forever — it passes initialization but the health probe keeps failing because external model checks time out or return 401.

### The Fix

**Option A — Use `/health/liveliness` instead of `/health`**

LiteLLM exposes three health endpoints:
- `/health` — checks ALL models (dangerous for health check)
- `/health/liveliness` — checks only that the server is running (correct for Docker)
- `/health/readiness` — checks DB connection only

```yaml
# In docker-compose.yml, change litellm healthcheck:
litellm:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:4000/health/liveliness"]
    interval: 30s
    timeout: 10s
    retries: 5
    start_period: 60s
```

**Option B — Add `HEALTHCHECK_ENDPOINT` environment variable**

```yaml
litellm:
  environment:
    HEALTHCHECK_ENDPOINT: "/health/liveliness"
    # ... rest of env vars
```

**This single change will unblock AnythingLLM, Flowise, N8N, and gdrive-ingestion simultaneously.**

**Verification:**
```bash
# Immediate check after restart:
docker exec ai-datasquiz-litellm-1 curl -s http://localhost:4000/health/liveliness
# Expected: {"status": "alive"}

# Then check Docker reports healthy:
docker ps --filter name=litellm --format "{{.Status}}"
# Expected: Up X minutes (healthy)

# Then check dependent services start:
docker ps | grep -E "anythingllm|flowise|n8n"
# Expected: All showing "Up" not "Created"
```

---

## Issue 2: RClone Command Syntax Error

### The Exact Error
```
Fatal error: unknown command "sh" for "rclone"
```

### The Exact Cause

The docker-compose YAML multi-line string is being passed directly to the `rclone` binary instead of to a shell. When Docker sees:

```yaml
command: >
  sh -c "..."
```

The `>` YAML folding scalar folds into a single string `sh -c "..."` which Docker passes as arguments to the container's **entrypoint**, which for the rclone image is the `rclone` binary itself. So it executes `rclone sh -c "..."` — hence "unknown command sh".

### The Fix

```yaml
rclone:
  # Override the entrypoint to use sh, then run the command
  entrypoint: ["/bin/sh", "-c"]
  command: >
    "
    echo 'Starting RClone sync daemon...' &&
    if [ ! -f /config/rclone/rclone.conf ]; then
      echo 'WARNING: rclone.conf not found at /config/rclone/rclone.conf' &&
      echo 'RClone cannot sync without configuration.' &&
      echo 'Run: docker exec -it ai-datasquiz-rclone-1 rclone config' &&
      sleep infinity;
    fi &&
    echo 'RClone config found, starting sync...' &&
    while true; do
      rclone sync gdrive:/ /gdrive \
        --config /config/rclone/rclone.conf \
        --log-level INFO \
        --transfers 4 \
        --checkers 8 \
        --contimeout 60s \
        --timeout 300s \
        --retries 3 \
        --low-level-retries 10 \
        --stats 30s;
      echo 'Sync complete, sleeping 300s...';
      sleep 300;
    done
    "
```

**Alternative fix (cleaner) — use a shell script:**

Create `/scripts/rclone-sync.sh`:
```bash
#!/bin/sh
set -e

CONFIG_FILE="/config/rclone/rclone.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "WARNING: rclone.conf not found"
    echo "Container will idle. Configure rclone first:"
    echo "  docker exec -it ai-datasquiz-rclone-1 sh"
    echo "  rclone config"
    sleep infinity
fi

echo "Starting RClone sync daemon..."
while true; do
    echo "[$(date)] Starting sync cycle..."
    rclone sync gdrive:/ /gdrive \
        --config "$CONFIG_FILE" \
        --log-level INFO \
        --transfers 4 \
        --checkers 8 \
        --contimeout 60s \
        --timeout 300s \
        --retries 3 \
        --stats 30s \
        2>&1
    echo "[$(date)] Sync complete. Next sync in 300s."
    sleep 300
done
```

Then in docker-compose:
```yaml
rclone:
  image: rclone/rclone:latest
  entrypoint: ["/bin/sh", "/scripts/rclone-sync.sh"]
  volumes:
    - ./scripts/rclone-sync.sh:/scripts/rclone-sync.sh:ro
    - rclone_config:/config/rclone
    - gdrive_data:/gdrive
  cap_add:
    - SYS_ADMIN
  devices:
    - /dev/fuse:/dev/fuse
  security_opt:
    - apparmor:unconfined
  restart: unless-stopped
```

**Verification:**
```bash
docker compose restart rclone
sleep 10
docker ps | grep rclone
# Expected: Up X seconds (no "Restarting" state)

docker logs ai-datasquiz-rclone-1 --tail 5
# Expected: Either "WARNING: rclone.conf not found" (if not configured)
#           OR "[timestamp] Starting sync cycle..."
```

---

## Issue 3: Services Waiting on LiteLLM — Cascade Check

Once LiteLLM health check is fixed, verify the `depends_on` conditions in docker-compose match what each service actually needs:

```yaml
# Each of these must have:
anythingllm:
  depends_on:
    litellm:
      condition: service_healthy  # This is correct
    postgres:
      condition: service_healthy  # Also needed for its own DB

flowise:
  depends_on:
    litellm:
      condition: service_healthy
    postgres:
      condition: service_healthy

n8n:
  depends_on:
    litellm:
      condition: service_healthy
    postgres:
      condition: service_healthy

gdrive-ingestion:
  depends_on:
    litellm:
      condition: service_healthy
    qdrant:
      condition: service_healthy
```

**Check after LiteLLM fix:**
```bash
# Watch services come up in sequence:
watch -n 5 'docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "litellm|anythingllm|flowise|n8n|ingestion"'
```

---

## Issue 4: OpenClaw Routing (Confirmed from Previous Analysis)

The audit shows OpenClaw itself is healthy on port 18789 → 8443. But the previous audit confirmed it was routing to code-server instead.

**Check the Caddy config is correct:**
```bash
# Verify what Caddy currently has for openclaw:
docker exec ai-datasquiz-caddy-1 caddy adapt --config /etc/caddy/Caddyfile 2>/dev/null | \
  python3 -m json.tool | grep -A 20 "openclaw"
```

**Expected result:** upstream should be `openclaw:8443` (internal container port), NOT `codeserver:8444`

**If wrong, the Caddyfile block must be:**
```caddy
https://openclaw.{$BASE_DOMAIN} {
    reverse_proxy openclaw:8443 {
        header_up Host {upstream_hostport}
        header_up X-Forwarded-Proto "https"
        header_up X-Real-IP {remote_host}
    }
}
```

Note: The audit says external port is 18789 → internal 8443. Caddy must proxy to the **internal** container port (8443), not the host-mapped port (18789).

---

## Issue 5: Dify Missing from Audit

Dify is completely absent from the service analysis. This means it either:
1. Was not included in the current docker-compose.yml, or
2. Failed so early it wasn't captured

**Check:**
```bash
docker ps -a | grep dify
# If no output: Dify was removed or never added
# If "Exited": Check logs
docker logs ai-datasquiz-dify-api-1 2>/dev/null || echo "Container does not exist"
```

If Dify was removed, Windsurf needs to restore these services from the README definition:
```yaml
# Minimum Dify services needed:
dify-api:
dify-worker:  
dify-web:
dify-sandbox:
dify-nginx:  # Internal routing — Caddy proxies to this
```

---

## Issue 6: Signal API Not in Audit

Signal API is also absent from the audit's service list (the audit cuts off mid-sentence at "codeser"). This suggests it was also not started or failed silently.

**Check:**
```bash
docker ps -a | grep signal
docker logs ai-datasquiz-signal-api-1 --tail 20
```

**If the QR endpoint issue persists, the registration flow is:**
```bash
# 1. Check if number is registered:
curl http://localhost:8080/v1/accounts

# 2. If empty, start registration:
PHONE="+1XXXXXXXXXX"  # Your actual number
curl -X POST "http://localhost:8080/v1/register/${PHONE}"

# 3. Enter the SMS verification code you receive:
curl -X POST "http://localhost:8080/v1/register/${PHONE}/verify/XXXXXX"

# 4. Now the QR link endpoint works for linking devices:
curl "http://localhost:8080/v1/qrcodelink?device_name=datasquiz-server"
```

---

## Issue 7: Ingestion Pipeline — GDrive → Qdrant

The audit confirms `gdrive-ingestion-1` exists and is waiting for LiteLLM. This means Windsurf **did build the service**. 

**After LiteLLM is fixed, verify ingestion actually works:**
```bash
# Once gdrive-ingestion starts:
docker logs ai-datasquiz-gdrive-ingestion-1 --tail 20

# Check if Qdrant collection was created:
curl http://localhost:6333/collections | python3 -m json.tool
# Expected: gdrive_documents collection present

# Check vector count after first sync:
curl http://localhost:6333/collections/gdrive_documents | python3 -m json.tool | grep vectors_count
```

**If RClone has no config yet, ingestion will have nothing to ingest — this is expected and correct behavior.**

---

## The Complete Fix Script for Windsurf

Tell Windsurf to make exactly these changes, nothing more:

### Change 1: `docker-compose.yml` — LiteLLM healthcheck (2 lines changed)

```yaml
# FIND this in litellm service:
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:4000/health"]

# REPLACE with:
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:4000/health/liveliness"]
  interval: 30s
  timeout: 15s
  retries: 10
  start_period: 90s
```

### Change 2: `docker-compose.yml` — RClone entrypoint fix

```yaml
# FIND rclone service command block and ADD entrypoint:
rclone:
  image: rclone/rclone:latest
  entrypoint: ["/bin/sh", "-c"]  # ADD THIS LINE
  command: |                      # CHANGE > to |
    if [ ! -f /config/rclone/rclone.conf ]; then
      echo 'rclone.conf not found - idling. Run: docker exec -it ai-datasquiz-rclone-1 rclone config'
      exec sleep infinity
    fi
    while true; do
      rclone sync gdrive:/ /gdrive --config /config/rclone/rclone.conf --log-level INFO
      sleep 300
    done
```

### Change 3: Verify Caddyfile openclaw block points to correct upstream

```caddy
# Must be:
https://openclaw.{$BASE_DOMAIN} {
    reverse_proxy openclaw:8443 {
        header_up X-Forwarded-Proto "https"
    }
}
# NOT codeserver:8444
```

### Restart sequence after changes:

```bash
# Apply changes:
docker compose up -d --no-deps litellm rclone

# Wait for LiteLLM to become healthy:
echo "Waiting for LiteLLM health..."
for i in $(seq 1 12); do
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' ai-datasquiz-litellm-1 2>/dev/null)
    echo "Attempt $i/12: $STATUS"
    if [ "$STATUS" = "healthy" ]; then
        echo "LiteLLM is healthy! Starting dependent services..."
        docker compose up -d anythingllm flowise n8n gdrive-ingestion
        break
    fi
    sleep 15
done

# Final status check:
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | \
  grep -E "NAME|litellm|anythingllm|flowise|n8n|rclone|ingestion"
```

---

## Priority Order and Expected Outcome

| Priority | Fix | Files Changed | Services Unblocked |
|----------|-----|---------------|-------------------|
| **P0** | LiteLLM healthcheck → `/health/liveliness` | `docker-compose.yml` (1 line) | AnythingLLM, Flowise, N8N, gdrive-ingestion |
| **P0** | RClone entrypoint syntax | `docker-compose.yml` (2 lines) | RClone sync |
| **P1** | Verify OpenClaw Caddy upstream | `Caddyfile` (1 line if wrong) | OpenClaw correct routing |
| **P2** | Restore Dify if missing | `docker-compose.yml` | Dify |
| **P2** | Signal registration | Manual CLI step | Signal messaging |
| **P3** | RClone config | Manual `rclone config` | GDrive sync → Ingestion |

**Two one-line fixes in `docker-compose.yml` will move the platform from 75% to 90%+ healthy.** The remaining 10% is Signal registration (manual phone step) and RClone configuration (OAuth to GDrive) — both are user-configuration steps, not code bugs.

---

## What to Tell Windsurf Explicitly

```
DO NOT regenerate docker-compose.yml from scratch.
DO NOT touch any service that is currently healthy.
DO NOT run script 0 (cleanup) or script 1 (setup).

Make exactly 2 changes to docker-compose.yml:

1. In the litellm service healthcheck, change:
   http://localhost:4000/health
   to:
   http://localhost:4000/health/liveliness
   
   This is because /health checks all external model APIs which 
   may be unreachable or have invalid keys, causing infinite "starting" state.
   /health/liveliness only checks that the process is running.

2. In the rclone service, add:
   entrypoint: ["/bin/sh", "-c"]
   
   Without this, Docker passes "sh -c ..." as arguments to the rclone 
   binary, which doesn't understand the "sh" command. The entrypoint 
   override routes execution through sh first.

After these 2 changes:
   docker compose up -d --no-deps litellm rclone
   
Wait 90 seconds, then verify:
   docker inspect --format='{{.State.Health.Status}}' ai-datasquiz-litellm-1
   # Must return: healthy
   
If healthy, start blocked services:
   docker compose up -d anythingllm flowise n8n gdrive-ingestion

Do not claim success until each service shows (healthy) in docker ps output.
```