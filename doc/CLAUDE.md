# Comprehensive Fix Blueprint — Final Sprint to 100%

## Reading the Actual State

Let me be precise about what the audit and codebase reveal before giving Windsurf actionable instructions.

---

## Critical Observation: LiteLLM Is the Blocker

The audit shows LiteLLM has been "initializing" for **13+ minutes** with `health: starting`. This is not a timing issue — this is a **startup loop caused by a schema conflict**. The logs reveal the exact problem:

```
Current Status: "Running prisma migrate deploy"
Issue: Read-only file system warning (expected in container)
Migration Progress: Generating baseline migration...
```

**The conflict:** The init container ran `prisma db push` (schema push), then LiteLLM itself is also trying to run `prisma migrate deploy` (migration-based). These two approaches are **incompatible on the same database**. When `prisma migrate deploy` finds a non-empty database without a `_prisma_migrations` table, it tries to create a baseline migration and hangs or fails in a read-only container filesystem.

---

## Issue Log: Every Problem and Its Exact Cause

### Issue 1: LiteLLM Never Becomes Healthy (Root Cause of Everything)

**What's happening:**
```
Init container: prisma db push (schema push — no migration table)
LiteLLM startup: prisma migrate deploy (looks for _prisma_migrations table — not found)
Result: LiteLLM tries to create baseline migration → needs to write to /tmp → 
        read-only filesystem warning → hangs → health check never passes → 
        ALL dependent services stay in "waiting" state forever
```

**The exact fix — choose ONE approach and be consistent:**

Option A (Recommended — simpler, works in containers):
```yaml
# In litellm-prisma-migrate init container:
command: >
  sh -c "
    SCHEMA_PATH=$(find /usr/local/lib -name 'schema.prisma' -path '*/litellm/*' 2>/dev/null | head -1)
    echo 'Found schema at: '$SCHEMA_PATH
    prisma db push --schema=$SCHEMA_PATH --accept-data-loss --skip-generate
    echo 'Schema push complete'
  "
```

Then in the main LiteLLM container, **prevent it from running migrations itself**:
```yaml
litellm:
  environment:
    DATABASE_URL: "postgresql://litellm:${POSTGRES_PASSWORD}@postgres:5432/litellm"
    LITELLM_MASTER_KEY: "${LITELLM_MASTER_KEY}"
    STORE_MODEL_IN_DB: "True"
    DISABLE_SCHEMA_UPDATE: "True"   # THIS IS THE MISSING FLAG
    PRISMA_SCHEMA_UPDATE: "false"   # Belt and suspenders
```

The flag `DISABLE_SCHEMA_UPDATE=True` tells LiteLLM not to attempt its own schema management. Windsurf has not set this, causing the double-migration conflict.

**Verification after fix:**
```bash
# Should return within 60 seconds of LiteLLM starting:
curl -s http://localhost:4000/health | python3 -m json.tool
# Expected: {"status": "healthy", "db": "connected"}

# Also verify the DB has data:
docker exec ai-datasquiz-postgres-1 psql -U ds-admin -d litellm -c "\dt"
# Expected: list of LiteLLM tables (LiteLLM_SpendLogs, LiteLLM_UserTable, etc.)
```

---

### Issue 2: Caddy `auto_https` Directive Parsing Error

The audit shows:
```
Current Issue: Configuration parsing error with auto_https directive (minor)
Status: Restarting every 12 seconds
```

This is **not minor** — Caddy restarting every 12 seconds means SSL certificates are never issued and routes flap.

**What's in the current Caddyfile (wrong):**
```caddy
{
  auto_https {
    ignore_loaded_certs
  }
  servers {
    protocol {
      strict_sni_host
      max_header_size 5kb
    }
  }
}
```

**The exact error:** `auto_https` is a top-level directive in the global block, not a block itself. The nested block syntax is wrong.

**Correct Caddyfile global block:**
```caddy
{
    admin 0.0.0.0:2019
    email admin@{$BASE_DOMAIN}
    
    # auto_https is a simple directive, not a block
    auto_https off
    
    servers {
        trusted_proxies static private_ranges
    }
}

# HTTP redirect — catch all
http:// {
    redir https://{host}{uri} permanent
}

https://litellm.{$BASE_DOMAIN} {
    reverse_proxy litellm:4000
    header {
        X-Forwarded-Proto "https"
        X-Real-IP {remote_host}
    }
}

https://chat.{$BASE_DOMAIN} {
    reverse_proxy open-webui:8080 {
        header_up Host {upstream_hostport}
        header_up X-Forwarded-Proto "https"
        header_up X-Real-IP {remote_host}
    }
    @websocket {
        header Connection *Upgrade*
        header Upgrade websocket
    }
    reverse_proxy @websocket open-webui:8080 {
        header_up Host {upstream_hostport}
        header_up Connection {>Connection}
        header_up Upgrade {>Upgrade}
    }
}

https://anythingllm.{$BASE_DOMAIN} {
    reverse_proxy anythingllm:3001 {
        header_up X-Forwarded-Proto "https"
    }
}

https://dify.{$BASE_DOMAIN} {
    # Point to Dify's internal nginx, NOT the API directly
    reverse_proxy dify-nginx:80 {
        header_up Host {upstream_hostport}
        header_up X-Forwarded-Proto "https"
        header_up X-Real-IP {remote_host}
    }
}

https://flowise.{$BASE_DOMAIN} {
    reverse_proxy flowise:3000 {
        header_up X-Forwarded-Proto "https"
    }
}

https://openclaw.{$BASE_DOMAIN} {
    # This MUST be its own server block — not a location inside another
    reverse_proxy openclaw:18789 {
        header_up X-Forwarded-Proto "https"
        header_up Host {upstream_hostport}
    }
}

https://opencode.{$BASE_DOMAIN} {
    reverse_proxy codeserver:8444 {
        header_up X-Forwarded-Proto "https"
    }
}

https://n8n.{$BASE_DOMAIN} {
    reverse_proxy n8n:5678 {
        header_up X-Forwarded-Proto "https"
        header_up X-Forwarded-Host {host}
    }
}

https://grafana.{$BASE_DOMAIN} {
    reverse_proxy grafana:3000 {
        header_up X-Forwarded-Proto "https"
    }
}

https://signal.{$BASE_DOMAIN} {
    reverse_proxy signal-api:8080 {
        header_up X-Forwarded-Proto "https"
    }
}

https://qdrant.{$BASE_DOMAIN} {
    reverse_proxy qdrant:6333 {
        header_up X-Forwarded-Proto "https"
    }
}
```

**Important note on `auto_https off`:** Since the platform is using Let's Encrypt via Tailscale or DNS challenge, check how certs are currently being managed. If Caddy is doing ACME automatically, use:
```caddy
{
    email admin@{$BASE_DOMAIN}
    # Remove auto_https block entirely — default behavior is correct
}
```

If using pre-existing certs (from Tailscale/certbot):
```caddy
{
    auto_https off  # Single directive, no block
}

https://litellm.{$BASE_DOMAIN} {
    tls /path/to/cert.pem /path/to/key.pem
    reverse_proxy litellm:4000
}
```

---

### Issue 3: OpenWebUI, Dify, Flowise — Waiting for LiteLLM That Never Becomes Healthy

Once LiteLLM is fixed (Issue 1), these services will start. However there are secondary issues:

**OpenWebUI** — needs these environment variables confirmed:
```yaml
open-webui:
  environment:
    OPENAI_API_BASE_URL: "http://litellm:4000/v1"
    OPENAI_API_KEY: "${LITELLM_MASTER_KEY}"
    WEBUI_URL: "https://chat.${BASE_DOMAIN}"    # Must match Caddy
    WEBUI_SECRET_KEY: "${OPENWEBUI_SECRET_KEY}"
    ENABLE_OLLAMA_API: "false"                  # Route through LiteLLM only
    VECTOR_DB: "qdrant"
    QDRANT_URI: "http://qdrant:6333"
```

**Dify** — confirm proxy target. The audit does not mention which port the proxy is hitting. Dify's internal nginx must be the target:
```yaml
# Verify in docker-compose.yml:
# dify-nginx service should expose port 80 internally
# Caddy should proxy to dify-nginx:80, NOT dify-api:5001
```

**Flowise** — check for silent crash. After LiteLLM is healthy, if Flowise still 502s:
```bash
docker logs ai-datasquiz-flowise-1 --tail 30
# Look for: "Cannot find module" or auth errors
```

Common Flowise issue — it needs `FLOWISE_SECRETKEY_OVERWRITE` set or it regenerates keys on every restart:
```yaml
flowise:
  environment:
    FLOWISE_USERNAME: "${FLOWISE_USERNAME}"
    FLOWISE_PASSWORD: "${FLOWISE_PASSWORD}"
    FLOWISE_SECRETKEY_OVERWRITE: "${FLOWISE_SECRET_KEY}"
    APIKEY_PATH: "/root/.flowise"
    DATABASE_PATH: "/root/.flowise"
    OPENAI_API_KEY: "${LITELLM_MASTER_KEY}"
    OPENAI_API_BASE: "http://litellm:4000/v1"
```

---

### Issue 4: OpenClaw Routing to Code-Server

The audit confirms the fix was attempted:
```
✅ OpenClaw routing corrected → port 18789 (was 8443)
```

But the problem persists. The reason is the **Caddy config restarting every 12 seconds** (Issue 2). When Caddy fails to parse and restarts, it may be loading a **cached or default config** that still has the wrong routing.

After fixing the Caddy config (Issue 2), verify:
```bash
# Check which config Caddy is actually using:
curl http://localhost:2019/config/ | python3 -m json.tool | grep -A5 "openclaw"

# Check current Caddyfile on disk:
cat /mnt/data/datasquiz/configs/caddy/Caddyfile | grep -A5 "openclaw"
```

If these differ, Caddy is not loading the file config — it's using the API. Tell Windsurf to ensure the Caddyfile is mounted and Caddy is started with:
```yaml
caddy:
  command: caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
  volumes:
    - /mnt/data/datasquiz/configs/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
```

---

### Issue 5: Signal API — QR Code Endpoint Failing

```
/v1/qrcodelink?device_name=signal-api → Not working
```

**The Signal REST API QR code endpoint exists only in the `native` mode AND requires the account to NOT be registered yet (for new registration) OR to be used for linking.**

Check sequence Windsurf must run:
```bash
# Step 1: What mode is it running in?
docker logs ai-datasquiz-signal-api-1 | head -20
# Look for: "mode: native" or "mode: json-rpc"

# Step 2: Is an account registered?
curl http://localhost:8080/v1/accounts
# Empty array = no account registered

# Step 3: If no account, initiate registration:
curl -X POST http://localhost:8080/v1/register/+YOUR_PHONE_NUMBER \
  -H "Content-Type: application/json" \
  -d '{"use_voice": false}'

# Step 4: Verify the QR link endpoint:
curl http://localhost:8080/v1/qrcodelink?device_name=signal-api
```

**Environment fix:**
```yaml
signal-api:
  environment:
    MODE: native
    SIGNAL_CLI_CONFIG: /home/.local/share/signal-cli
    AUTO_RECEIVE_SCHEDULE: "0 * * * *"
    # NOT json-rpc mode
```

---

### Issue 6: RClone Not Mounting/Syncing

The audit says RClone is "READY (not deployed by default)" with flag `ENABLE_RCLONE`. This means **it's not running at all**.

The fix has two parts:

**Part A — Enable and configure:**
```bash
# In .env:
ENABLE_RCLONE=true

# In script 3, add the enable check:
if [ "${ENABLE_RCLONE:-false}" = "true" ]; then
    docker compose --profile rclone up -d
fi
```

**Part B — The rclone config file must exist before starting:**
```bash
# Windsurf must check if config exists:
ls /mnt/data/datasquiz/configs/rclone/rclone.conf

# If not, the container will start but fail silently
# Script 3 must handle this:
if [ ! -f "/mnt/data/datasquiz/configs/rclone/rclone.conf" ]; then
    echo "WARNING: rclone.conf not found. RClone will not sync."
    echo "Run: docker exec -it ai-datasquiz-rclone-1 rclone config"
    echo "Then re-run this script"
fi
```

**The FUSE issue — verify capabilities are set:**
```yaml
rclone:
  cap_add:
    - SYS_ADMIN
  devices:
    - /dev/fuse:/dev/fuse
  security_opt:
    - apparmor:unconfined
  privileged: false  # Do NOT use privileged:true as Windsurf sometimes does
```

---

### Issue 7: Ingestion Pipeline — Not Implemented

The audit lists it as "ENHANCEMENT OPPORTUNITY" but the README defines it as a **core feature**. Windsurf has not built this.

The minimum viable ingestion pipeline Windsurf needs to create:

**File: `/mnt/data/datasquiz/ingestion/ingest.py`**

Key logic outline (Windsurf writes the full implementation):
```python
"""
GDrive → Qdrant ingestion pipeline
Reads from: /data/gdrive-sync (shared volume with rclone)
Writes to: Qdrant collection 'gdrive_documents'
Embeds via: LiteLLM /v1/embeddings endpoint
State tracking: /data/ingestion-state/processed_files.json (hash-based dedup)
"""

SUPPORTED_EXTENSIONS = ['.pdf', '.docx', '.txt', '.md', '.csv']
CHUNK_SIZE = 512          # tokens
CHUNK_OVERLAP = 50        # tokens  
VECTOR_DIMENSIONS = 1536  # match the embedding model (text-embedding-3-small)
COLLECTION_NAME = "gdrive_documents"
BATCH_SIZE = 100          # upsert batch size to Qdrant

# Required pip packages:
# qdrant-client, pypdf, python-docx, tiktoken, requests, watchdog
```

**Docker service Windsurf needs to add:**
```yaml
gdrive-ingestion:
  build:
    context: ./ingestion
    dockerfile: Dockerfile
  depends_on:
    qdrant:
      condition: service_healthy
    litellm:
      condition: service_healthy
  volumes:
    - gdrive_data:/data/gdrive-sync:ro
    - ingestion_state:/data/ingestion-state
  environment:
    QDRANT_URL: "http://qdrant:6333"
    LITELLM_URL: "http://litellm:4000"
    LITELLM_MASTER_KEY: "${LITELLM_MASTER_KEY}"
    EMBEDDING_MODEL: "text-embedding-3-small"
    COLLECTION_NAME: "gdrive_documents"
    SYNC_DIR: "/data/gdrive-sync"
    WATCH_INTERVAL: "300"  # 5 minutes
  restart: unless-stopped
  profiles:
    - ingestion  # Only start when explicitly enabled
```

**Script 3 trigger Windsurf needs to add:**
```bash
# At end of script 3, if rclone is enabled:
if [ "${ENABLE_RCLONE:-false}" = "true" ]; then
    # Trigger initial sync
    docker compose --profile rclone up -d
    sleep 30  # Wait for first sync
    
    # Start ingestion if gdrive has content
    SYNC_DIR="/mnt/data/datasquiz/gdrive"
    FILE_COUNT=$(find "$SYNC_DIR" -type f | wc -l)
    if [ "$FILE_COUNT" -gt 0 ]; then
        docker compose --profile ingestion up -d
        echo "Ingestion pipeline started with $FILE_COUNT files"
    fi
fi
```

---

## The Exact Implementation Order for Windsurf

Tell Windsurf to implement in this precise sequence with validation at each step:

### Step 1: Fix LiteLLM Schema Conflict
```
Files to modify:
  - docker-compose.yml: Add DISABLE_SCHEMA_UPDATE=True to litellm service
  - docker-compose.yml: Change init container command to use prisma db push --skip-generate
  - docker-compose.yml: Remove any PRISMA_MIGRATE environment variables from main litellm service

Validation:
  docker compose restart litellm
  # Wait 60 seconds
  curl http://localhost:4000/health
  # Must return: {"status":"healthy"}
  # If still failing after 2 minutes, check logs:
  docker logs ai-datasquiz-litellm-1 --tail 20
```

### Step 2: Fix Caddy Configuration
```
Files to modify:
  - /mnt/data/datasquiz/configs/caddy/Caddyfile: Replace global block
  - docker-compose.yml: Ensure caddy command explicitly loads Caddyfile

Validation:
  docker compose restart caddy
  # Should NOT restart in loop
  docker ps | grep caddy  # Check uptime > 30 seconds
  curl -I https://litellm.datasquiz.net
  # Must return: HTTP/2 200 or appropriate response (not connection refused)
```

### Step 3: Verify All Dependent Services Start
```
After Steps 1 and 2, these should auto-start:
  - open-webui
  - anythingllm  
  - flowise
  - dify (all containers)
  - openclaw
  - n8n

Validation for each:
  docker ps | grep -E "webui|anythingllm|flowise|dify|openclaw|n8n"
  # All should show "Up X minutes" not "Restarting"
```

### Step 4: Fix Signal API
```
Files to modify:
  - docker-compose.yml: Ensure MODE=native for signal-api

Validation:
  curl http://localhost:8080/v1/accounts
  # If empty, registration needed (manual step)
```

### Step 5: Enable RClone and Build Ingestion Pipeline
```
Files to create:
  - /ingestion/Dockerfile
  - /ingestion/ingest.py
  - /ingestion/requirements.txt

Files to modify:
  - docker-compose.yml: Add gdrive-ingestion service
  - scripts/3-configure-services.sh: Add ingestion trigger

Validation:
  curl http://localhost:6333/collections/gdrive_documents
  # After first sync and ingest: vector_count > 0
```

---

## What to Tell Windsurf Explicitly

```
STOP claiming 100% success based on container startup state.

A service is only healthy when:
1. Its health endpoint returns HTTP 200 with expected JSON
2. Its external URL through Caddy returns HTTP 200
3. Its core functionality works (not just "container is running")

The single blocking issue right now is:
  DISABLE_SCHEMA_UPDATE=True is missing from litellm environment
  This causes LiteLLM to hang trying to run prisma migrate deploy 
  after the init container already ran prisma db push
  These two commands are incompatible on the same database

Fix that one environment variable first.
Then fix the Caddy global block syntax (auto_https is not a block directive).
Everything else will cascade into working state.

Do not touch any service that is currently working.
Do not regenerate docker-compose.yml from scratch.
Make surgical changes only.
```

---

## Quick Reference: Known Good vs Known Broken

| Service | State | Action Needed |
|---------|-------|---------------|
| PostgreSQL | ✅ Working | None |
| Redis | ✅ Working | None |
| Qdrant | ✅ Working | None |
| Ollama | ✅ Working | None |
| LiteLLM | ❌ Hanging | Add `DISABLE_SCHEMA_UPDATE=True` |
| Caddy | ❌ Restart loop | Fix `auto_https` directive syntax |
| OpenWebUI | ⏸️ Blocked | Unblocks after LiteLLM fix |
| AnythingLLM | ⏸️ Blocked | Unblocks after LiteLLM fix |
| Flowise | ⏸️ Blocked | Unblocks after LiteLLM fix |
| Dify | ⏸️ Blocked | Unblocks + verify proxy target is dify-nginx:80 |
| OpenClaw | ❌ Wrong route | Unblocks after Caddy fix |
| Signal | ❌ Config | Set MODE=native, register account |
| RClone | ⏸️ Disabled | Set ENABLE_RCLONE=true + verify rclone.conf |
| Ingestion | ❌ Not built | Build ingestion service (new feature) |
| Grafana | ✅ Working | None |

Two fixes unlock eight services. That is the entire story.